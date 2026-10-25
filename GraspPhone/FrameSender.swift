import CoreImage
import Foundation
import GraspKit

/// Picks which camera frames go to the Mac, shrinks them to JPEG and times the round trip.
///
/// Live frames go out a few times a second, one at a time: the next waits until the Mac
/// has acknowledged the last, so a slow link drops frames instead of falling behind.
/// A capture goes out on the next frame regardless, or, for a fling, from a moment before
/// the phone started moving, so it isn't blurred.
final class FrameSender: @unchecked Sendable {
    static let liveFPS = 4.0
    static let liveLongSide = 720.0
    static let liveQuality = 0.5
    static let captureLongSide = 2000.0
    static let captureQuality = 0.85

    /// Called on the main queue with each capture as sent, so the phone can show it.
    var onCapture: (@MainActor (UUID, Data) -> Void)?

    private let link: MultipeerLink
    private let context = CIContext()

    // `offer` runs on the camera queue and the rest on the main queue; the lock guards these.
    private let lock = NSLock()
    private var isLive = true
    private var wantsCapture = false
    private var captureLookBack = 0.0
    private var inFlight: (id: UUID, sentAt: Double)?
    private var lastLiveAt = -Double.infinity
    private var roundTripMs: Double?
    /// Sharp frames from the last moment, kept so a fling can send one from before it moved.
    private var recent: [(time: Double, image: CGImage)] = []
    private var captureCount = 0
    private var lastSnapshotAt = -Double.infinity

    init(link: MultipeerLink) {
        self.link = link
    }

    func setLive(_ live: Bool) {
        lock.withLock { isLive = live }
    }

    /// Sends a sharp, full-size frame: the next one, or one from `lookBack` seconds ago.
    func requestCapture(lookBack: Double = 0) {
        lock.withLock {
            wantsCapture = true
            captureLookBack = lookBack
        }
    }

    /// How many captures have gone out.
    var capturesSent: Int {
        lock.withLock { captureCount }
    }

    /// Records the Mac's receipt and returns the round trip in milliseconds.
    func acknowledge(frameID: UUID, sentAt: Double) -> Double {
        let ms = (Self.now() - sentAt) * 1000
        lock.withLock {
            roundTripMs = ms
            if inFlight?.id == frameID { inFlight = nil }
        }
        return ms
    }

    /// Offers a camera frame. `captureImage`, if given, is sent instead when a capture is due
    /// (the simulator's demo props), decided under the same lock so a tap can't slip between.
    func offer(_ image: CIImage, captureImage: CIImage? = nil) {
        guard link.isConnected else { return }
        let time = Self.now()
        keepSnapshot(of: image, at: time)

        let (purpose, source, lastRoundTrip): (LinkFrame.Purpose?, CIImage, Double?) = lock.withLock {
            if wantsCapture {
                wantsCapture = false
                captureCount += 1
                let cutoff = time - captureLookBack
                let earlier = captureLookBack > 0 ? recent.last(where: { $0.time <= cutoff }) : nil
                return (.capture, captureImage ?? earlier.map { CIImage(cgImage: $0.image) } ?? image, roundTripMs)
            }
            // Give up waiting on a frame the Mac never acknowledged after a second.
            let linkIsFree = inFlight.map { time - $0.sentAt > 1 } ?? true
            guard isLive, linkIsFree, time - lastLiveAt >= 1 / Self.liveFPS else { return (nil, image, nil) }
            lastLiveAt = time
            return (.live, image, roundTripMs)
        }
        guard let purpose, let jpeg = encode(source, purpose: purpose) else { return }

        let frame = LinkFrame(jpeg: jpeg, purpose: purpose, sentAt: Self.now(), roundTripMs: lastRoundTrip)
        if purpose == .live {
            lock.withLock { inFlight = (frame.id, frame.sentAt) }
        }
        link.send(.frame(frame))
        if purpose == .capture, let onCapture {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { onCapture(frame.id, jpeg) }
            }
        }
    }

    /// About ten frames a second for the last 0.6 s.
    private func keepSnapshot(of image: CIImage, at time: Double) {
        guard time - lastSnapshotAt >= 0.1, let snapshot = context.createCGImage(image, from: image.extent) else { return }
        lastSnapshotAt = time
        lock.withLock {
            recent.append((time, snapshot))
            recent.removeAll { time - $0.time > 0.6 }
        }
    }

    private func encode(_ image: CIImage, purpose: LinkFrame.Purpose) -> Data? {
        let longSide = purpose == .live ? Self.liveLongSide : Self.captureLongSide
        let scale = min(1, longSide / max(image.extent.width, image.extent.height))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let quality = purpose == .live ? Self.liveQuality : Self.captureQuality
        return context.jpegRepresentation(
            of: scaled,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
        )
    }

    private static func now() -> Double {
        ProcessInfo.processInfo.systemUptime
    }
}
