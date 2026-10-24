import CoreImage
import Foundation
import GraspKit

/// Picks which camera frames go to the Mac, shrinks them to JPEG and times the round trip.
///
/// Live frames go out a few times a second, one at a time: the next waits until the Mac
/// has acknowledged the last, so a slow link drops frames instead of falling behind.
/// A capture goes out on the next frame regardless.
final class FrameSender: @unchecked Sendable {
    static let liveFPS = 4.0
    static let liveLongSide = 720.0
    static let liveQuality = 0.5
    static let captureLongSide = 2000.0
    static let captureQuality = 0.85

    private let link: MultipeerLink
    private let context = CIContext()

    // `offer` runs on the camera queue and the rest on the main queue; the lock guards these.
    private let lock = NSLock()
    private var isLive = true
    private var wantsCapture = false
    private var inFlight: (id: UUID, sentAt: Double)?
    private var lastLiveAt = -Double.infinity
    private var roundTripMs: Double?

    init(link: MultipeerLink) {
        self.link = link
    }

    func setLive(_ live: Bool) {
        lock.withLock { isLive = live }
    }

    /// Sends the next frame sharp and full size.
    func requestCapture() {
        lock.withLock { wantsCapture = true }
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

    func offer(_ image: CIImage) {
        guard link.isConnected else { return }
        let time = Self.now()

        let (purpose, lastRoundTrip): (LinkFrame.Purpose?, Double?) = lock.withLock {
            if wantsCapture {
                wantsCapture = false
                return (.capture, roundTripMs)
            }
            // Give up waiting on a frame the Mac never acknowledged after a second.
            let linkIsFree = inFlight.map { time - $0.sentAt > 1 } ?? true
            guard isLive, linkIsFree, time - lastLiveAt >= 1 / Self.liveFPS else { return (nil, nil) }
            lastLiveAt = time
            return (.live, roundTripMs)
        }
        guard let purpose, let jpeg = encode(image, purpose: purpose) else { return }

        let frame = LinkFrame(jpeg: jpeg, purpose: purpose, sentAt: Self.now(), roundTripMs: lastRoundTrip)
        if purpose == .live {
            lock.withLock { inFlight = (frame.id, frame.sentAt) }
        }
        link.send(.frame(frame))
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
