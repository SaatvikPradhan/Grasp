import AppKit
import GraspKit
import Observation
import SystemConfiguration

/// The Mac's side of the phone link: hosts the connection and keeps the latest frames.
@MainActor @Observable
final class PhoneLink {
    private(set) var state = MultipeerLink.State.searching
    private(set) var liveImage: NSImage?
    private(set) var lastCapture: NSImage?
    private(set) var captureCount = 0
    /// The phone's measured round trip; half of it is roughly how long a frame takes to arrive.
    private(set) var roundTripMs: Double?
    private(set) var framesPerSecond = 0.0
    /// Called with the JPEG of every capture the phone sends.
    @ObservationIgnored var onCapture: ((Data) -> Void)?

    @ObservationIgnored private let link = MultipeerLink(
        role: .host,
        // Host.current().localizedName can stall on a DNS lookup; this reads the name locally.
        displayName: SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Grasp Mac"
    )
    @ObservationIgnored private var started = false
    @ObservationIgnored private var framesInWindow = 0
    @ObservationIgnored private var windowStart = Date()

    var oneWayMs: Double? { roundTripMs.map { $0 / 2 } }

    func start() {
        guard !started else { return }
        started = true
        link.onState = { [weak self] state in
            self?.state = state
        }
        link.onMessage = { [weak self] message in
            self?.handle(message)
        }
        link.start()
    }

    private func handle(_ message: LinkMessage) {
        guard case .frame(let frame) = message else { return }
        // Acknowledge first so the phone's timing covers the trip, not our decoding.
        link.send(.received(frameID: frame.id, sentAt: frame.sentAt))

        if let ms = frame.roundTripMs { roundTripMs = ms }
        let image = NSImage(data: frame.jpeg)
        switch frame.purpose {
        case .live:
            liveImage = image
            countFrame()
        case .capture:
            lastCapture = image
            captureCount += 1
            onCapture?(frame.jpeg)
        }
    }

    private func countFrame() {
        framesInWindow += 1
        let elapsed = Date().timeIntervalSince(windowStart)
        if elapsed >= 1 {
            framesPerSecond = Double(framesInWindow) / elapsed
            framesInWindow = 0
            windowStart = Date()
        }
    }
}
