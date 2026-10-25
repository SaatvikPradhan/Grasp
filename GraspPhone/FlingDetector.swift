import CoreMotion
import Foundation

/// Spots a deliberate flick toward the laptop: hold the phone still on the paper for a
/// moment (aiming), then flick its top away from you. Walking around, picking the phone up
/// or setting it down doesn't count, because none of them start from a held aim.
final class FlingDetector: @unchecked Sendable {
    /// The flick: rotation (rad/s) at least this fast…
    static let flickSpin = 9.0
    /// …mostly about the phone's side-to-side axis, which is tipping the top away.
    static let tipShare = 0.6
    /// It has to burst out of an aim: the phone held under this much rotation (rad/s)…
    static let aimStill = 1.0
    /// …for at least this long…
    static let aimDuration = 0.4
    /// …in a hand, which always trembles a little; a phone lying on a table doesn't.
    static let handTremor = 0.02
    /// Seconds before another flick can fire.
    static let cooldown = 2.0

    /// Called on the main actor.
    var onFling: (@MainActor () -> Void)?

    private let motion = CMMotionManager()
    private let queue = OperationQueue()

    // Touched only on `queue`.
    private var stillSince: Double?
    private var lastStill = -Double.infinity
    private var aimLength = 0.0
    private var aimTremor = 0.0
    private var lastFling = -Double.infinity

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        queue.maxConcurrentOperationCount = 1
        motion.deviceMotionUpdateInterval = 1.0 / 60
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            handle(rotation: data.rotationRate, at: data.timestamp)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }

    private func handle(rotation r: CMRotationRate, at time: Double) {
        let spin = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()

        if spin < Self.aimStill {
            if stillSince == nil {
                stillSince = time
                aimTremor = 0
            }
            lastStill = time
            aimLength = time - (stillSince ?? time)
            aimTremor = max(aimTremor, spin)
            return
        }
        stillSince = nil

        let burstsFromAim = aimLength >= Self.aimDuration && aimTremor >= Self.handTremor && time - lastStill <= 0.25
        guard spin > Self.flickSpin, abs(r.x) >= Self.tipShare * spin, burstsFromAim,
              time - lastFling > Self.cooldown else { return }
        lastFling = time
        aimLength = 0
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.onFling?() }
        }
    }
}
