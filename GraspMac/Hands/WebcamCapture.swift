@preconcurrency import AVFoundation

/// The Mac's built-in camera, delivering frames on a background queue.
final class WebcamCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum StartResult {
        case running, denied, noCamera
        case failed(String)
    }

    let session = AVCaptureSession()
    /// Called on the frame queue for every frame. Set before `start()`.
    var onFrame: (@Sendable (CMSampleBuffer) -> Void)?

    private let sessionQueue = DispatchQueue(label: "grasp.webcam.session")
    private let frameQueue = DispatchQueue(label: "grasp.webcam.frames", qos: .userInteractive)

    func start() async -> StartResult {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return .denied }
        default:
            return .denied
        }

        guard let camera = Self.pickCamera() else { return .noCamera }
        do {
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            if session.canSetSessionPreset(.hd1280x720) {
                session.sessionPreset = .hd1280x720
            }
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else { return .failed("cannot use \(camera.localizedName)") }
            session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            output.setSampleBufferDelegate(self, queue: frameQueue)
            guard session.canAddOutput(output) else { return .failed("cannot read frames") }
            session.addOutput(output)
        } catch {
            return .failed(error.localizedDescription)
        }

        let session = self.session
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.startRunning()
                continuation.resume()
            }
        }
        return .running
    }

    /// Prefers the built-in camera, so an iPhone nearby (Continuity Camera) does not take over hand tracking.
    private static func pickCamera() -> AVCaptureDevice? {
        let builtIn = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
        return builtIn.first ?? AVCaptureDevice.default(for: .video)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onFrame?(sampleBuffer)
    }
}
