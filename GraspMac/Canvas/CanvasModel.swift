import GraspKit
import Observation
import SwiftUI

struct ChartCard: Identifiable, Equatable {
    let id = UUID()
    var center: CGPoint
    var size = CGSize(width: 460, height: 300)
    var loan: LoanTerms
    /// The term the salesperson pitched, which every other term is compared against.
    var pitchTermMonths: Int

    var frame: CGRect {
        CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}

/// Cards on the canvas and what each hand is holding.
@MainActor @Observable
final class CanvasModel {
    static let termRange = 24...84
    static let termStep = 12

    var cards: [ChartCard] = []
    private(set) var hands: [TrackedHand] = []
    private(set) var canvasSize = CGSize(width: 1280, height: 800)
    var showDebug = true
    /// Degrees of wrist turn per term step (12 months).
    var degreesPerStep = 20.0

    /// What a pinching hand grabbed when the pinch began. `cardID` is nil for empty canvas.
    private struct Grip {
        var cardID: UUID?
        var offset = CGSize.zero
        var startCenter = CGPoint.zero
        var startTerm = 0
        var snappedBack = false
    }

    private var grips: [Int: Grip] = [:]
    @ObservationIgnored private var hasLaidOut = false
    @ObservationIgnored private var mouseDragStart: (id: UUID, center: CGPoint)?

    init() {
        resetLayout()
    }

    func resetLayout() {
        grips = [:]
        cards = [
            ChartCard(
                center: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
                loan: .demoContract,
                pitchTermMonths: LoanTerms.demoContract.termMonths
            ),
        ]
    }

    func setCanvasSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        canvasSize = size
        if !hasLaidOut {
            hasLaidOut = true
            resetLayout()
        }
    }

    // MARK: Hands

    func point(for hand: TrackedHand) -> CGPoint {
        CGPoint(x: hand.cursor.x * canvasSize.width, y: hand.cursor.y * canvasSize.height)
    }

    func isHeld(_ cardID: UUID) -> Bool {
        grips.values.contains { $0.cardID == cardID }
    }

    func cursorState(for hand: TrackedHand) -> HandCursor.Mode {
        guard hand.isPinching else {
            return cards.contains { $0.frame.contains(point(for: hand)) } ? .overCard : .open
        }
        if hand.pinch == .twist, let id = grips[hand.id]?.cardID, let card = cards.first(where: { $0.id == id }) {
            let range = Self.termRange
            let fraction = Double(card.loan.termMonths - range.lowerBound) / Double(range.upperBound - range.lowerBound)
            return .twist(fraction: fraction, label: "\(card.loan.termMonths) mo")
        }
        return .pinch
    }

    /// Called once per camera frame with every tracked hand.
    func apply(_ newHands: [TrackedHand]) {
        let live = Set(newHands.map(\.id))
        for id in grips.keys where !live.contains(id) {
            grips[id] = nil
        }
        for hand in newHands {
            track(hand)
        }
        hands = newHands
    }

    private func track(_ hand: TrackedHand) {
        guard hand.isPinching else {
            grips[hand.id] = nil
            return
        }
        let p = point(for: hand)

        if grips[hand.id] == nil {
            // A pinch grabs the top card under it, or nothing; it never picks one up later.
            if let index = cards.lastIndex(where: { $0.frame.contains(p) }) {
                let card = cards.remove(at: index)
                cards.append(card)
                grips[hand.id] = Grip(
                    cardID: card.id,
                    offset: CGSize(width: card.center.x - p.x, height: card.center.y - p.y),
                    startCenter: card.center,
                    startTerm: card.loan.termMonths
                )
            } else {
                grips[hand.id] = Grip()
            }
        }

        guard var grip = grips[hand.id], let id = grip.cardID,
              let index = cards.firstIndex(where: { $0.id == id }) else { return }

        if hand.pinch == .twist {
            // The card followed the hand while the pinch was undecided; a twist puts it back.
            if !grip.snappedBack {
                cards[index].center = grip.startCenter
                grip.snappedBack = true
                grips[hand.id] = grip
            }
            let steps = Int((hand.twist * 180 / .pi / degreesPerStep).rounded())
            setTerm(of: index, to: grip.startTerm + steps * Self.termStep)
        } else {
            cards[index].center = clamped(CGPoint(x: p.x + grip.offset.width, y: p.y + grip.offset.height))
        }
    }

    // MARK: Mouse and keyboard

    func mouseDrag(_ id: UUID, translation: CGSize) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        if mouseDragStart?.id != id {
            mouseDragStart = (id, cards[index].center)
        }
        guard let start = mouseDragStart else { return }
        cards[index].center = clamped(CGPoint(x: start.center.x + translation.width, y: start.center.y + translation.height))
    }

    func endMouseDrag() {
        mouseDragStart = nil
    }

    /// Changes the frontmost card's term by whole steps.
    func stepTerm(by steps: Int) {
        guard let index = cards.indices.last else { return }
        setTerm(of: index, to: cards[index].loan.termMonths + steps * Self.termStep)
    }

    // MARK: Helpers

    private func setTerm(of index: Int, to months: Int) {
        let term = min(max(months, Self.termRange.lowerBound), Self.termRange.upperBound)
        if cards[index].loan.termMonths != term {
            cards[index].loan.termMonths = term
        }
    }

    /// Keeps at least a third of a card on the canvas.
    private func clamped(_ center: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(center.x, 80), canvasSize.width - 80),
            y: min(max(center.y, 60), canvasSize.height - 60)
        )
    }
}
