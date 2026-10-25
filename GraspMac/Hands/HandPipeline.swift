import AVFoundation
import GraspKit
import Observation
import os

/// Webcam → Vision → gesture engine → canvas. Tracking runs on the webcam's queue;
/// results land on the main actor once per frame.
@MainActor @Observable
final class HandPipeline {
    enum Status: Equatable {
        case starting, running, cameraDenied, noCamera
        case failed(String)
    }

    private(set) var status = Status.starting
    /// Frames tracked per second; gate G1 wants about 30.
    private(set) var fps = 0.0
    /// Camera image width over height.
    private(set) var aspect = 16.0 / 9.0
    var config = GestureConfig() {
        didSet { worker.setConfig(config) }
    }
    /// Called on the main actor with every frame's hands, after the canvas has them.
    @ObservationIgnored var onHands: (([TrackedHand]) -> Void)?

    @ObservationIgnored let capture = WebcamCapture()
    @ObservationIgnored private let worker = HandWorker()
    @ObservationIgnored private var started = false

    func start(feeding canvas: CanvasModel) async {
        guard !started else { return }
        started = true

        let worker = self.worker
        capture.onFrame = { [weak self] buffer in
            guard let output = worker.process(buffer) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    canvas.apply(output.hands)
                    guard let self else { return }
                    self.onHands?(output.hands)
                    if self.aspect != output.aspect { self.aspect = output.aspect }
                    if let fps = output.fps { self.fps = fps }
                }
            }
        }

        switch await capture.start() {
        case .running: status = .running
        case .denied: status = .cameraDenied
        case .noCamera: status = .noCamera
        case .failed(let message): status = .failed(message)
        }
    }
}

/// The part of the pipeline that lives on the webcam queue.
private final class HandWorker: @unchecked Sendable {
    struct Output {
        var hands: [TrackedHand]
        var aspect: Double
        /// Set about once a second.
        var fps: Double?
    }

    // Touched only on the webcam queue, except `pendingConfig`, which the lock guards.
    private let tracker = HandTracker()
    private var engine = GestureEngine()
    private let pendingConfig = OSAllocatedUnfairLock<GestureConfig?>(initialState: nil)
    private var framesInWindow = 0
    private var windowStart: Double?

    func setConfig(_ config: GestureConfig) {
        pendingConfig.withLock { $0 = config }
    }

    func process(_ buffer: CMSampleBuffer) -> Output? {
        let newConfig = pendingConfig.withLock { pending -> GestureConfig? in
            defer { pending = nil }
            return pending
        }
        if let newConfig { engine.config = newConfig }

        guard let frame = tracker.detect(in: buffer) else { return nil }
        let hands = engine.update(frame)

        var fps: Double?
        framesInWindow += 1
        if let start = windowStart {
            if frame.time - start >= 1 {
                fps = Double(framesInWindow) / (frame.time - start)
                framesInWindow = 0
                windowStart = frame.time
            }
        } else {
            windowStart = frame.time
        }
        return Output(hands: hands, aspect: frame.aspect, fps: fps)
    }
}
