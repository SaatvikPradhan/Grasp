@preconcurrency import AVFoundation

/// The back camera, delivering upright frames on a background queue.
final class PhoneCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    /// Called on the frame queue for every frame. Set before `start()`.
    var onFrame: (@Sendable (CVPixelBuffer) -> Void)?

    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "grasp.phone.camera.session")
    private let frameQueue = DispatchQueue(label: "grasp.phone.camera.frames", qos: .userInteractive)
    private var device: AVCaptureDevice?
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var rotationObservations: [NSKeyValueObservation] = []

    /// Returns false when the camera is denied or missing.
    func start() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }

        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        }
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: frameQueue)
        session.addOutput(output)
        session.commitConfiguration()
        self.device = device

        let session = self.session
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.startRunning()
                continuation.resume()
            }
        }
        return true
    }

    /// Keeps the preview and the sent frames upright as the phone turns.
    @MainActor
    func attach(_ previewLayer: AVCaptureVideoPreviewLayer) {
        guard let device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotation = coordinator
        Self.rotate(previewLayer.connection, to: coordinator.videoRotationAngleForHorizonLevelPreview)
        Self.rotate(output.connection(with: .video), to: coordinator.videoRotationAngleForHorizonLevelCapture)

        let output = self.output
        let previewConnection = previewLayer.connection
        rotationObservations = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                DispatchQueue.main.async { Self.rotate(previewConnection, to: angle) }
            },
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: .new) { coordinator, _ in
                Self.rotate(output.connection(with: .video), to: coordinator.videoRotationAngleForHorizonLevelCapture)
            },
        ]
    }

    private static func rotate(_ connection: AVCaptureConnection?, to angle: CGFloat) {
        guard let connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(buffer)
    }
}
