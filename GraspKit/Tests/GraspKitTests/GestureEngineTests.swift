import CoreGraphics
import Foundation
import Testing
@testable import GraspKit

/// Drives the engine with synthetic hands, since a test has no webcam.
struct GestureEngineTests {
    /// A hand with its wrist at `wrist`, fingers pointing along `angle` (radians, y down,
    /// so -π/2 is straight up), palm 0.1 long, and thumb and index tips `gap` apart.
    func hand(wrist: CGPoint, angle: Double = -.pi / 2, gap: Double, chirality: HandChirality = .unknown) -> HandSample {
        func along(_ length: Double, side: Double = 0) -> CGPoint {
            CGPoint(
                x: wrist.x + cos(angle) * length - sin(angle) * side,
                y: wrist.y + sin(angle) * length + cos(angle) * side
            )
        }
        return HandSample(chirality: chirality, joints: [
            .wrist: wrist,
            .middleMCP: along(0.1),
            .thumbTip: along(0.17, side: -gap / 2),
            .indexTip: along(0.17, side: gap / 2),
        ])
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
