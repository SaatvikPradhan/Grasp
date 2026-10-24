import CoreGraphics
import Foundation

public struct GestureConfig: Sendable, Equatable {
    /// A pinch starts when the thumb-to-index gap falls below this fraction of palm length
    /// (wrist to middle knuckle) and ends when it rises above `pinchExit`. Measuring against
    /// the palm keeps the thresholds the same near and far from the camera.
    public var pinchEnter: Double = 0.30
    public var pinchExit: Double = 0.45
    /// The part of the camera image that maps onto the whole canvas, so the edges of the
    /// canvas are reachable without the hand leaving the frame.
    public var reach = CGRect(x: 0.15, y: 0.10, width: 0.70, height: 0.70)
    /// One Euro smoothing for the cursor, in canvas units (0...1 per second).
    public var smoothingMinCutoff: Double = 1.2
    public var smoothingBeta: Double = 4.0
    /// While pinched, turning the hand this many degrees locks the pinch into a twist.
    public var twistLockDegrees: Double = 15
    /// While pinched, moving the wrist this far (canvas units) locks the pinch into a drag.
    /// The wrist is used rather than the fingertips because a twist swings the fingertips
    /// around the wrist, while a drag moves the whole hand.
    public var dragLock: Double = 0.03
    /// Keep a hand, and its pinch, alive this long after Vision loses it.
    public var lostHandGrace: Double = 0.25
    /// Farthest a wrist may move between frames (camera units) and still count as the same hand.
    public var matchDistance: Double = 0.3

    public init() {}

    /// Maps a point in the camera image to canvas units, clamped to the canvas.
    public func canvasPoint(fromCamera point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max((point.x - reach.minX) / reach.width, 0), 1),
            y: min(max((point.y - reach.minY) / reach.height, 0), 1)
        )
    }
}

/// A hand the engine is following from frame to frame.
public struct TrackedHand: Identifiable, Sendable, Equatable {
    public enum Pinch: Sendable, Equatable {
        case open
        /// Pinched, but not yet moved or turned enough to count as a drag or a twist.
        case undecided
        case drag
        case twist
    }

    public let id: Int
    public var chirality: HandChirality
    /// Smoothed point between thumb and index tips, in canvas units (0...1 from the top left).
    public var cursor: CGPoint
    public var pinch: Pinch = .open
    /// Radians turned since the twist locked. Clockwise, as you see it on screen, is positive.
    public var twist: Double = 0
    /// Thumb-to-index gap over palm length; small means pinched.
    public var pinchRatio: Double
    /// Vision's points for this frame, in camera units, for drawing a skeleton.
    public var joints: [HandJoint: CGPoint]

    public var isPinching: Bool { pinch != .open }
}

/// Turns raw hand points into cursors, pinches, drags and twists.
///
/// Feed it every camera frame with `update(_:)`. It matches hands across frames, smooths
/// the cursor, applies pinch hysteresis, and decides whether each pinch is a drag or a twist.
public struct GestureEngine: Sendable {
    public var config: GestureConfig
    public private(set) var hands: [TrackedHand] = []

    private var states: [Int: HandState] = [:]
    private var nextID = 1

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
    }

    @discardableResult
    public mutating func update(_ frame: HandFrame) -> [TrackedHand] {
        let measurements = frame.hands.compactMap { Measurement($0, aspect: frame.aspect) }

        // Match new measurements to known hands, closest wrists first.
        var pairs: [(cost: Double, id: Int, index: Int)] = []
        for (id, state) in states {
            for (index, measurement) in measurements.enumerated() {
                var cost = distance(state.lastWrist, measurement.wrist)
                if state.hand.chirality != .unknown, measurement.chirality != .unknown,
                   state.hand.chirality != measurement.chirality {
                    cost += 0.2
                }
                if cost < config.matchDistance { pairs.append((cost, id, index)) }
            }
        }
        pairs.sort { $0.cost < $1.cost }

        var unmatchedIDs = Set(states.keys)
        var usedIndexes = Set<Int>()
        for pair in pairs where unmatchedIDs.contains(pair.id) && !usedIndexes.contains(pair.index) {
            unmatchedIDs.remove(pair.id)
            usedIndexes.insert(pair.index)
            states[pair.id]?.update(with: measurements[pair.index], at: frame.time, config: config)
        }
        for (index, measurement) in measurements.enumerated() where !usedIndexes.contains(index) {
            states[nextID] = HandState(id: nextID, measurement: measurement, at: frame.time, config: config)
            nextID += 1
        }
        for id in unmatchedIDs where frame.time - (states[id]?.lastSeen ?? 0) > config.lostHandGrace {
            states[id] = nil
        }

        hands = states.values.map(\.hand).sorted { $0.id < $1.id }
        return hands
    }
}

/// What one hand sample says about the gesture, in square units (x scaled by aspect).
private struct Measurement {
    var chirality: HandChirality
    var joints: [HandJoint: CGPoint]
    var wrist: CGPoint
    /// Between thumb and index tips; nil when Vision lost either tip.
    var pinchPoint: CGPoint?
    var pinchRatio: Double?
    /// Direction from wrist to middle knuckle, in radians, y down.
    var angle: Double

    init?(_ sample: HandSample, aspect: Double) {
        guard let wrist = sample.joints[.wrist], let knuckle = sample.joints[.middleMCP] else { return nil }
        func square(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * aspect, y: p.y) }

        let palm = distance(square(wrist), square(knuckle))
        guard palm > 0.01 else { return nil }

        chirality = sample.chirality
        joints = sample.joints
        self.wrist = wrist
        angle = atan2(square(knuckle).y - square(wrist).y, square(knuckle).x - square(wrist).x)
        if let thumb = sample.joints[.thumbTip], let index = sample.joints[.indexTip] {
            pinchPoint = CGPoint(x: (thumb.x + index.x) / 2, y: (thumb.y + index.y) / 2)
            pinchRatio = distance(square(thumb), square(index)) / palm
        }
    }
}

private struct HandState: Sendable {
    var hand: TrackedHand
    var lastSeen: Double
    var lastWrist: CGPoint

    private var cursorFilter: PointFilter
    private var angleFilter = OneEuroFilter(minCutoff: 1.0, beta: 0.5)
    private var rawAngle: Double
    private var unwrappedAngle: Double
    private var angle: Double
    private var pinchStartWrist = CGPoint.zero
    private var pinchStartAngle = 0.0
    private var twistStartAngle = 0.0

    init(id: Int, measurement m: Measurement, at time: Double, config: GestureConfig) {
        cursorFilter = PointFilter(minCutoff: config.smoothingMinCutoff, beta: config.smoothingBeta)
        let cursor = cursorFilter.filter(config.canvasPoint(fromCamera: m.pinchPoint ?? m.wrist), at: time)
        hand = TrackedHand(id: id, chirality: m.chirality, cursor: cursor, pinchRatio: m.pinchRatio ?? 1, joints: m.joints)
        lastSeen = time
        lastWrist = m.wrist
        rawAngle = m.angle
        unwrappedAngle = m.angle
        angle = angleFilter.filter(m.angle, at: time)
        updatePinch(m, config: config)
    }

    mutating func update(with m: Measurement, at time: Double, config: GestureConfig) {
        lastSeen = time
        lastWrist = m.wrist
        hand.joints = m.joints
        if m.chirality != .unknown { hand.chirality = m.chirality }

        if let pinchPoint = m.pinchPoint {
            cursorFilter.tune(minCutoff: config.smoothingMinCutoff, beta: config.smoothingBeta)
            hand.cursor = cursorFilter.filter(config.canvasPoint(fromCamera: pinchPoint), at: time)
        }

        // Unwrap so a turn across ±180° keeps counting instead of jumping.
        var delta = (m.angle - rawAngle).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
        rawAngle = m.angle
        unwrappedAngle += delta
        angle = angleFilter.filter(unwrappedAngle, at: time)

        updatePinch(m, config: config)
    }

    private mutating func updatePinch(_ m: Measurement, config: GestureConfig) {
        // Without both fingertips, hold the last pinch state rather than dropping a grab.
        guard let ratio = m.pinchRatio else { return }
        hand.pinchRatio = ratio

        if hand.pinch == .open {
            guard ratio < config.pinchEnter else { return }
            hand.pinch = .undecided
            hand.twist = 0
            pinchStartWrist = m.wrist
            pinchStartAngle = angle
            return
        }
        if ratio > config.pinchExit {
            hand.pinch = .open
            hand.twist = 0
            return
        }
        if hand.pinch == .undecided {
            let turned = abs(angle - pinchStartAngle) * 180 / .pi
            let moved = distance(
                CGPoint(x: m.wrist.x / config.reach.width, y: m.wrist.y / config.reach.height),
                CGPoint(x: pinchStartWrist.x / config.reach.width, y: pinchStartWrist.y / config.reach.height)
            )
            if turned >= config.twistLockDegrees {
                hand.pinch = .twist
                twistStartAngle = angle
            } else if moved >= config.dragLock * 2.5 || (moved >= config.dragLock && turned < config.twistLockDegrees * 0.66) {
                hand.pinch = .drag
            }
        }
        if hand.pinch == .twist {
            hand.twist = angle - twistStartAngle
        }
    }
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
    hypot(a.x - b.x, a.y - b.y)
}
