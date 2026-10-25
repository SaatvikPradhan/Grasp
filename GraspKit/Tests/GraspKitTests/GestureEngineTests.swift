import CoreGraphics
import Foundation
import Testing
@testable import GraspKit

/// Drives the engine with synthetic hands, since a test has no webcam.
struct GestureEngineTests {
    /// A hand with its wrist at `wrist`, fingers pointing along `angle` (radians, y down,
    /// so -π/2 is straight up), palm 0.1 long, and thumb and index tips `gap` apart.
    /// `fingers` adds middle, ring and little tips that far from the wrist: 0.18 is an
    /// open palm, 0.08 a fist.
    func hand(wrist: CGPoint, angle: Double = -.pi / 2, gap: Double, fingers: Double? = nil,
              index: Double = 0.17, chirality: HandChirality = .unknown) -> HandSample {
        func along(_ length: Double, side: Double = 0) -> CGPoint {
            CGPoint(
                x: wrist.x + cos(angle) * length - sin(angle) * side,
                y: wrist.y + sin(angle) * length + cos(angle) * side
            )
        }
        var joints: [HandJoint: CGPoint] = [
            .wrist: wrist,
            .middleMCP: along(0.1),
            .thumbTip: along(index, side: -gap / 2),
            .indexTip: along(index, side: gap / 2),
        ]
        if let fingers {
            joints[.middleTip] = along(fingers, side: 0.02)
            joints[.ringTip] = along(fingers, side: 0.04)
            joints[.littleTip] = along(fingers * 0.85, side: 0.06)
        }
        return HandSample(chirality: chirality, joints: joints)
    }

    /// Runs frames at 30 fps from `start` and returns the hands after the last one.
    @discardableResult
    func run(_ engine: inout GestureEngine, frames: Int, from start: Int = 0, _ hands: (Int) -> [HandSample]) -> [TrackedHand] {
        var result: [TrackedHand] = []
        for frame in start..<(start + frames) {
            result = engine.update(HandFrame(hands: hands(frame), time: Double(frame) / 30, aspect: 1))
        }
        return result
    }

    let center = CGPoint(x: 0.5, y: 0.6)

    @Test func openHandIsNotPinching() {
        var engine = GestureEngine()
        let hands = run(&engine, frames: 10) { _ in [hand(wrist: center, gap: 0.08)] }
        #expect(hands.count == 1)
        #expect(hands[0].pinch == .open)
    }

    @Test func pinchHasHysteresis() {
        var engine = GestureEngine()
        run(&engine, frames: 5) { _ in [hand(wrist: center, gap: 0.02)] }
        #expect(engine.hands[0].pinch == .undecided)

        // 0.038 / 0.1 = 0.38: above the enter threshold but below the exit, so still pinched.
        run(&engine, frames: 5, from: 5) { _ in [hand(wrist: center, gap: 0.038)] }
        #expect(engine.hands[0].isPinching)

        run(&engine, frames: 5, from: 10) { _ in [hand(wrist: center, gap: 0.06)] }
        #expect(engine.hands[0].pinch == .open)
    }

    @Test func pinchStaysSteadyEvenWithOutSetEqualToIn() {
        var config = GestureConfig()
        config.pinchEnter = 0.30
        config.pinchExit = 0.30   // no gap: a pinch would flicker without the enforced minimum
        var engine = GestureEngine(config: config)
        run(&engine, frames: 5) { _ in [hand(wrist: center, gap: 0.02)] }
        // 0.032 / 0.1 = 0.32: just over both sliders, but under in + the minimum gap.
        run(&engine, frames: 5, from: 5) { _ in [hand(wrist: center, gap: 0.032)] }
        #expect(engine.hands[0].isPinching)
    }

    @Test func movingWhilePinchedIsADrag() {
        var engine = GestureEngine()
        run(&engine, frames: 5) { _ in [hand(wrist: center, gap: 0.02)] }
        let start = engine.hands[0].cursor
        let hands = run(&engine, frames: 30, from: 5) { frame in
            [hand(wrist: CGPoint(x: center.x + Double(frame - 5) * 0.005, y: center.y), gap: 0.02)]
        }
        #expect(hands[0].pinch == .drag)
        #expect(hands[0].cursor.x > start.x + 0.1)
        #expect(hands[0].twist == 0)
    }

    @Test func turningWhilePinchedIsATwist() {
        var engine = GestureEngine()
        run(&engine, frames: 5) { _ in [hand(wrist: center, gap: 0.02)] }
        // Turn 45° clockwise around a still wrist over half a second, then hold.
        let hands = run(&engine, frames: 30, from: 5) { frame in
            let turned = min(Double(frame - 5) / 15, 1) * .pi / 4
            return [hand(wrist: center, angle: -.pi / 2 + turned, gap: 0.02)]
        }
        #expect(hands[0].pinch == .twist)
        #expect(hands[0].twist > 0.3)   // most of the 30° left after the 15° lock
        #expect(hands[0].twist < 0.6)
    }

    @Test func counterClockwiseTwistIsNegative() {
        var engine = GestureEngine()
        run(&engine, frames: 5) { _ in [hand(wrist: center, gap: 0.02)] }
        let hands = run(&engine, frames: 30, from: 5) { frame in
            let turned = min(Double(frame - 5) / 15, 1) * .pi / 4
            return [hand(wrist: center, angle: -.pi / 2 - turned, gap: 0.02)]
        }
        #expect(hands[0].pinch == .twist)
        #expect(hands[0].twist < -0.3)
    }

    @Test func briefDropoutKeepsTheGrab() {
        var engine = GestureEngine()
        run(&engine, frames: 5) { _ in [hand(wrist: center, gap: 0.02)] }
        let id = engine.hands[0].id

        run(&engine, frames: 3, from: 5) { _ in [] }   // 0.1 s with no hand
        #expect(engine.hands.first?.id == id)
        #expect(engine.hands.first?.isPinching == true)

        run(&engine, frames: 2, from: 8) { _ in [hand(wrist: center, gap: 0.02)] }
        #expect(engine.hands.map(\.id) == [id])

        run(&engine, frames: 15, from: 10) { _ in [] }  // 0.5 s: gone
        #expect(engine.hands.isEmpty)
    }

    @Test func twoHandsKeepTheirIDs() {
        var engine = GestureEngine()
        let left = CGPoint(x: 0.3, y: 0.6), right = CGPoint(x: 0.7, y: 0.6)
        run(&engine, frames: 3) { _ in [hand(wrist: left, gap: 0.08), hand(wrist: right, gap: 0.08)] }
        let ids = engine.hands.map(\.id)
        #expect(ids.count == 2)

        // Vision returns them in the other order and both drift a little.
        let hands = run(&engine, frames: 10, from: 3) { frame in
            let drift = Double(frame - 3) * 0.003
            return [hand(wrist: CGPoint(x: right.x - drift, y: right.y), gap: 0.08),
                    hand(wrist: CGPoint(x: left.x + drift, y: left.y), gap: 0.08)]
        }
        #expect(hands.map(\.id) == ids)
        #expect(hands[0].cursor.x < hands[1].cursor.x)
    }

    @Test func reachMapsToTheWholeCanvas() {
        let config = GestureConfig()
        #expect(config.canvasPoint(fromCamera: CGPoint(x: 0.15, y: 0.10)) == .zero)
        #expect(config.canvasPoint(fromCamera: CGPoint(x: 0.85, y: 0.80)) == CGPoint(x: 1, y: 1))
        #expect(config.canvasPoint(fromCamera: CGPoint(x: 0, y: 1)) == CGPoint(x: 0, y: 1))
    }
}

/// Open-palm swipes, which switch a chart between bars and lines.
struct SwipeTests {
    let base = GestureEngineTests()

    /// Moves a hand sideways by `step` camera units a frame for `frames` frames, after
    /// holding still for 5, and returns every swipe seen.
    func swipes(step: Double, frames: Int, from startX: Double = 0.3, gap: Double = 0.08, fingers: Double = 0.18) -> [Swipe] {
        var engine = GestureEngine()
        var seen: [Swipe] = []
        for frame in 0..<(5 + frames) {
            let x = startX + Double(max(frame - 5, 0)) * step
            let hands = engine.update(HandFrame(
                hands: [base.hand(wrist: CGPoint(x: x, y: 0.6), gap: gap, fingers: fingers)],
                time: Double(frame) / 30, aspect: 1
            ))
            seen += hands.compactMap(\.swipe)
        }
        return seen
    }

    @Test func fastOpenPalmSwipesOnce() {
        let seen = swipes(step: 0.02, frames: 12)   // 0.24 camera units in 0.4 s
        #expect(seen.count == 1)
        #expect(seen.first?.direction == .right)
    }

    @Test func swipesLeftToo() {
        #expect(swipes(step: -0.02, frames: 12, from: 0.75).first?.direction == .left)
    }

    @Test func slowMoveIsNotASwipe() {
        #expect(swipes(step: 0.004, frames: 60).isEmpty)   // same distance over 2 s
    }

    @Test func pinchedHandDoesNotSwipe() {
        #expect(swipes(step: 0.02, frames: 12, gap: 0.02).isEmpty)
    }

    @Test func fistDoesNotSwipe() {
        #expect(swipes(step: 0.02, frames: 12, fingers: 0.08).isEmpty)
    }

    @Test func openPalmIsReported() {
        var engine = GestureEngine()
        let open = engine.update(HandFrame(hands: [base.hand(wrist: CGPoint(x: 0.5, y: 0.6), gap: 0.08, fingers: 0.18)], time: 0, aspect: 1))
        #expect(open.first?.isOpenPalm == true)
    }
}

/// A fist (grab the mic) starts talking; it must never be mistaken for a pinch.
struct FistTests {
    let base = GestureEngineTests()
    let center = CGPoint(x: 0.5, y: 0.6)

    func run(frames: Int, _ sample: HandSample) -> TrackedHand? {
        var engine = GestureEngine()
        var last: TrackedHand?
        for frame in 0..<frames {
            last = engine.update(HandFrame(hands: [sample], time: Double(frame) / 30, aspect: 1)).first
        }
        return last
    }

    /// All four fingertips curled back near the knuckles, thumb against the index.
    var fist: HandSample { base.hand(wrist: center, gap: 0.01, fingers: 0.09, index: 0.095) }

    @Test func heldFistTalksAndNeverPinches() {
        let early = run(frames: 4, fist)   // about 0.1 s: not yet
        #expect(early?.isFist == false)
        #expect(early?.isPinching == false)

        let held = run(frames: 12, fist)   // about 0.4 s
        #expect(held?.isFist == true)
        #expect(held?.isPinching == false)
    }

    @Test func pinchWithCurledFingersIsStillAPinch() {
        // Index out to meet the thumb, the other fingers curled: a normal pinch.
        let hand = run(frames: 12, base.hand(wrist: center, gap: 0.02, fingers: 0.09))
        #expect(hand?.isPinching == true)
        #expect(hand?.isFist == false)
    }

    @Test func openHandIsNotAFist() {
        let hand = run(frames: 12, base.hand(wrist: center, gap: 0.08, fingers: 0.18))
        #expect(hand?.isFist == false)
    }
}
