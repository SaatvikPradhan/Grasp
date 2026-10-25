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
    public var twistLockDegrees: Double = 12
    /// While pinched, moving the hand this far (canvas units) locks the pinch into a drag.
    /// "Moving" is whichever moved less, the wrist or the pinch: a twist turns the hand around
    /// one of them (the wrist, or fingers holding a knob), while a drag moves both.
    public var dragLock: Double = 0.03
    /// A drag that started this recently can still become a twist, if the hand then turns
    /// this many degrees without going anywhere.
    public var lateTwistWindow: Double = 0.5
    public var lateTwistDegrees: Double = 22
    /// Keep a hand, and its pinch, alive this long after Vision loses it.
    public var lostHandGrace: Double = 0.25
    /// Farthest a wrist may move between frames (camera units) and still count as the same hand.
    public var matchDistance: Double = 0.3
    /// A palm is open when its fingertips average at least this many palm lengths from the wrist.
    public var openPalm: Double = 1.5
    /// A swipe is an open palm moving this far sideways (canvas units)…
    public var swipeDistance: Double = 0.22
    /// …within this many seconds…
    public var swipeWindow: Double = 0.35
    /// …after which that hand can't swipe again for this long.
    public var swipeCooldown: Double = 0.8
    /// A fist (grab the mic, to talk): the index tip within this many palm lengths of the
    /// wrist, and the other fingertips within `fistOthers`. A pinch keeps the index out further,
    /// even with the other fingers curled.
    public var fistIndex: Double = 1.1
    public var fistOthers: Double = 1.2
    /// …and, when Vision sees the index knuckle, the index tip curled back within this many
    /// palm lengths of it. A pinching index bends to meet the thumb but stays out.
    public var fistIndexCurl: Double = 0.65
    /// A fist ends once the fingers open past these.
    public var fistIndexExit: Double = 1.45
    public var fistOthersExit: Double = 1.4
    /// Seconds a fist is held before it counts, so passing through one doesn't.
    public var fistHold: Double = 0.25
    /// A thumbs up: the thumb tip at least this many palm lengths from the index tip and the
    /// highest point of the hand, pointing within 45° of straight up, the other fingers curled.
    public var thumbsUpGap: Double = 0.6
    /// Seconds a thumbs up is held before it counts…
    public var thumbsUpHold: Double = 0.3
    /// …after which that hand can't give another for this long.
    public var thumbsUpCooldown: Double = 1.2

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
    /// Fingers spread, as for a swipe.
    public var isOpenPalm = false
    /// A held fist, like gripping a microphone: talk while it's closed.
    public var isFist = false
    /// Set only on the frame a swipe is recognized.
    public var swipe: Swipe?
    /// Set only on the frame a held thumbs up is recognized: put this away.
    public var thumbsUp = false

    public var isPinching: Bool { pinch != .open }
}

/// An open hand sweeping sideways: switches the chart under it between bars and lines.
public struct Swipe: Sendable, Equatable {
    public enum Direction: Sendable, Equatable {
        case left, right
    }

    public var direction: Direction
    /// The cursor where the swipe began, in canvas units; the card there is the one swiped.
    public var origin: CGPoint
}

/// Turns raw hand points into cursors, pinches, drags, twists, swipes, fists and thumbs up.
///
/// Feed it every camera frame with `update(_:)`. It matches hands across frames, smooths
/// the cursor, applies pinch hysteresis, decides whether each pinch is a drag or a twist,
/// spots open-palm swipes, and tells a fist (talk) from a pinch (grab) and a thumbs up.
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
        let measurements = frame.hands.compactMap { Measurement($0, aspect: frame.aspect, config: config) }

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
    /// Thumb-to-index gap and palm length, in square units, for measuring a held pinch against
    /// the palm as it was when the pinch began (turning the hand foreshortens the palm).
    var pinchGap: Double?
    var palm: Double
    /// Direction from wrist to middle knuckle, in radians, y down.
    var angle: Double
    /// Average fingertip distance from the wrist over palm length; nil without enough fingertips.
    var openness: Double?
    /// Index fingertip distance from the wrist over palm length.
    var indexReach: Double?
    /// Middle, ring and little fingertips' average distance from the wrist over palm length.
    var otherReach: Double?
    /// Index tip distance from the index knuckle over palm length: small when the finger is curled.
    var indexCurl: Double?
    /// Thumb up and out, the highest point of the hand, the other fingers curled.
    var isThumbsUp = false

    init?(_ sample: HandSample, aspect: Double, config: GestureConfig) {
        guard let wrist = sample.joints[.wrist], let knuckle = sample.joints[.middleMCP] else { return nil }
        func square(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * aspect, y: p.y) }

        let palm = distance(square(wrist), square(knuckle))
        guard palm > 0.01 else { return nil }

        chirality = sample.chirality
        joints = sample.joints
        self.wrist = wrist
        self.palm = palm
        angle = atan2(square(knuckle).y - square(wrist).y, square(knuckle).x - square(wrist).x)
        if let thumb = sample.joints[.thumbTip], let index = sample.joints[.indexTip] {
            pinchPoint = CGPoint(x: (thumb.x + index.x) / 2, y: (thumb.y + index.y) / 2)
            pinchGap = distance(square(thumb), square(index))
            pinchRatio = distance(square(thumb), square(index)) / palm
        }
        func reach(_ point: CGPoint) -> Double { distance(square(point), square(wrist)) / palm }
        let tips = [HandJoint.indexTip, .middleTip, .ringTip, .littleTip].compactMap { sample.joints[$0] }
        if tips.count >= 3 {
            openness = tips.map(reach).reduce(0, +) / Double(tips.count)
        }
        indexReach = sample.joints[.indexTip].map(reach)
        let others = [HandJoint.middleTip, .ringTip, .littleTip].compactMap { sample.joints[$0] }
        if others.count >= 2 {
            otherReach = others.map(reach).reduce(0, +) / Double(others.count)
        }
        if let tip = sample.joints[.indexTip], let knuckle = sample.joints[.indexMCP] {
            indexCurl = distance(square(tip), square(knuckle)) / palm
        }
        isThumbsUp = Self.thumbsUp(sample, palm: palm, minimumGap: config.thumbsUpGap, square: square)
    }

    /// A thumb pointing up and away from curled fingers.
    private static func thumbsUp(_ sample: HandSample, palm: Double, minimumGap: Double, square: (CGPoint) -> CGPoint) -> Bool {
        let j = sample.joints
        guard let thumb = j[.thumbTip], let index = j[.indexTip], let wrist = j[.wrist] else { return false }
        let base = j[.thumbMP] ?? j[.thumbCMC] ?? wrist
        let up = CGPoint(x: square(thumb).x - square(base).x, y: square(thumb).y - square(base).y)
        let length = hypot(up.x, up.y)
        guard length > 0.25 * palm,
              -up.y / length > cos(.pi / 4),   // within 45° of straight up (y grows downward)
              distance(square(thumb), square(index)) / palm >= minimumGap else { return false }
        // The thumb tip is the top of the hand: above every other tip and knuckle by a margin.
        let rest: [HandJoint] = [.indexTip, .middleTip, .ringTip, .littleTip, .indexMCP, .middleMCP, .ringMCP, .littleMCP]
        guard rest.compactMap({ j[$0] }).allSatisfy({ $0.y - thumb.y > 0.2 * palm }) else { return false }
        // The fingers are curled: their tips close to the wrist.
        let tips = [HandJoint.indexTip, .middleTip, .ringTip, .littleTip].compactMap { j[$0] }
        guard tips.count >= 3 else { return false }
        let reach = tips.map { distance(square($0), square(wrist)) / palm }.reduce(0, +) / Double(tips.count)
        return reach < 1.25
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
    private var pinchStartPoint = CGPoint.zero
    private var pinchStartPalm = 0.0
    private var pinchStartAngle = 0.0
    private var pinchStartTime = 0.0
    private var twistStartAngle = 0.0
    /// Recent wrist positions (canvas units) while the palm is open, for spotting a swipe.
    private var swipeTrail: [(time: Double, wrist: CGPoint, cursor: CGPoint)] = []
    private var lastSwipeAt = -Double.infinity
    /// The hand is shaped like a fist right now (with hysteresis), and since when.
    private var fistShape = false
    private var fistSince: Double?
    /// A thumbs up is held since then; the last one counted at `lastThumbsUpAt`.
    private var thumbsUpSince: Double?
    private var lastThumbsUpAt = -Double.infinity

    init(id: Int, measurement m: Measurement, at time: Double, config: GestureConfig) {
        cursorFilter = PointFilter(minCutoff: config.smoothingMinCutoff, beta: config.smoothingBeta)
        let cursor = cursorFilter.filter(config.canvasPoint(fromCamera: m.pinchPoint ?? m.wrist), at: time)
        hand = TrackedHand(id: id, chirality: m.chirality, cursor: cursor, pinchRatio: m.pinchRatio ?? 1, joints: m.joints)
        lastSeen = time
        lastWrist = m.wrist
        rawAngle = m.angle
        unwrappedAngle = m.angle
        angle = angleFilter.filter(m.angle, at: time)
        updateFist(m, at: time, config: config)
        updatePinch(m, at: time, config: config)
        updateSwipe(m, at: time, config: config)
        updateThumbsUp(m, at: time, config: config)
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

        updateFist(m, at: time, config: config)
        updatePinch(m, at: time, config: config)
        updateSwipe(m, at: time, config: config)
        updateThumbsUp(m, at: time, config: config)
    }

    private mutating func updateFist(_ m: Measurement, at time: Double, config: GestureConfig) {
        guard let index = m.indexReach, let others = m.otherReach else { return }
        if m.isThumbsUp {
            fistShape = false
        } else if fistShape {
            fistShape = index <= config.fistIndexExit && others <= config.fistOthersExit
        } else {
            fistShape = index < config.fistIndex && others < config.fistOthers && (m.indexCurl ?? 0) < config.fistIndexCurl
        }
        if fistShape {
            if fistSince == nil { fistSince = time }
        } else {
            fistSince = nil
        }
        // A pinching hand keeps pinching; curling the fingers while twisting doesn't start talking.
        hand.isFist = !hand.isPinching && time - (fistSince ?? time) >= config.fistHold && fistSince != nil
    }

    static let minimumHysteresis = 0.05

    private mutating func updateThumbsUp(_ m: Measurement, at time: Double, config: GestureConfig) {
        hand.thumbsUp = false
        guard m.isThumbsUp, !hand.isPinching else {
            thumbsUpSince = nil
            return
        }
        if thumbsUpSince == nil { thumbsUpSince = time }
        if let since = thumbsUpSince, time - since >= config.thumbsUpHold, time - lastThumbsUpAt >= config.thumbsUpCooldown {
            hand.thumbsUp = true
            lastThumbsUpAt = time
        }
    }

    private mutating func updateSwipe(_ m: Measurement, at time: Double, config: GestureConfig) {
        hand.swipe = nil
        hand.isOpenPalm = (m.openness ?? 0) >= config.openPalm
        guard hand.isOpenPalm, hand.pinch == .open else {
            swipeTrail.removeAll()
            return
        }

        let wrist = config.canvasPoint(fromCamera: m.wrist)
        swipeTrail.append((time, wrist, hand.cursor))
        swipeTrail.removeAll { time - $0.time > config.swipeWindow }
        guard let start = swipeTrail.first, time - lastSwipeAt >= config.swipeCooldown else { return }

        let dx = wrist.x - start.wrist.x
        let dy = wrist.y - start.wrist.y
        guard abs(dx) >= config.swipeDistance, abs(dy) < abs(dx) * 0.7 else { return }
        hand.swipe = Swipe(direction: dx > 0 ? .right : .left, origin: start.cursor)
        lastSwipeAt = time
        swipeTrail.removeAll()
    }

    private mutating func updatePinch(_ m: Measurement, at time: Double, config: GestureConfig) {
        // Without both fingertips, hold the last pinch state rather than dropping a grab.
        guard var ratio = m.pinchRatio, let gap = m.pinchGap else { return }
        // A held pinch is measured against the palm as it was when it began, so turning the hand
        // (which foreshortens the palm) doesn't let go.
        if hand.isPinching { ratio = gap / max(m.palm, pinchStartPalm * 0.75) }
        hand.pinchRatio = ratio

        // A fist brings the thumb to the index too, but it isn't a pinch: closing into one ends
        // a pinch that hasn't grabbed anything yet. A drag or twist keeps going.
        if fistShape, hand.pinch == .open || hand.pinch == .undecided {
            hand.pinch = .open
            return
        }

        if hand.pinch == .open {
            guard ratio < config.pinchEnter, !m.isThumbsUp else { return }
            hand.pinch = .undecided
            hand.twist = 0
            pinchStartWrist = m.wrist
            pinchStartPoint = m.pinchPoint ?? m.wrist
            pinchStartPalm = m.palm
            pinchStartAngle = angle
            pinchStartTime = time
            return
        }
        // Release needs a clearly wider gap than grabbing, or the pinch flickers on and off
        // at the threshold; enforce that even if the sliders are set too close.
        if ratio > max(config.pinchExit, config.pinchEnter + Self.minimumHysteresis) {
            hand.pinch = .open
            hand.twist = 0
            return
        }
        let turned = abs(angle - pinchStartAngle) * 180 / .pi
        func moved(_ from: CGPoint, _ to: CGPoint) -> Double {
            distance(CGPoint(x: to.x / config.reach.width, y: to.y / config.reach.height),
                     CGPoint(x: from.x / config.reach.width, y: from.y / config.reach.height))
        }
        // Whichever stayed put: a twist turns around the wrist or around the pinch, a drag moves both.
        let travel = min(moved(pinchStartWrist, m.wrist), moved(pinchStartPoint, m.pinchPoint ?? m.wrist))
        if hand.pinch == .undecided {
            if turned >= config.twistLockDegrees, travel < config.dragLock * 3 {
                hand.pinch = .twist
                twistStartAngle = angle
            } else if travel >= config.dragLock * 2.5 || (travel >= config.dragLock && turned < config.twistLockDegrees * 0.5) {
                hand.pinch = .drag
            }
        } else if hand.pinch == .drag, time - pinchStartTime <= config.lateTwistWindow,
                  turned >= config.lateTwistDegrees, travel < config.dragLock * 3 {
            // It looked like a drag at first, but the hand is turning in place.
            hand.pinch = .twist
            twistStartAngle = pinchStartAngle + (angle > pinchStartAngle ? 1 : -1) * config.twistLockDegrees * .pi / 180
        }
        if hand.pinch == .twist {
            hand.twist = angle - twistStartAngle
        }
    }
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
    hypot(a.x - b.x, a.y - b.y)
}
