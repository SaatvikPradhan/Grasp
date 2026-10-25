import GraspKit
import Observation
import SwiftUI

/// Cards on the canvas and what each hand is doing to them.
@MainActor @Observable
final class CanvasModel {
    /// Two cards merge when this much of the smaller one overlaps the other…
    static let mergeOverlap = 0.45
    /// …and light up as merge candidates from this much.
    static let candidateOverlap = 0.15

    var cards: [Card] = []
    private(set) var hands: [TrackedHand] = []
    private(set) var canvasSize = CGSize(width: 1280, height: 800)
    /// Cards being pushed into each other, lit up before they merge.
    private(set) var mergeCandidates: Set<UUID> = []
    var showDebug = true
    /// Degrees of wrist turn per dial step (12 months on a loan).
    var degreesPerStep = 20.0

    /// What a pinching hand grabbed when the pinch began. `cardID` is nil for empty canvas.
    private struct Grip {
        var cardID: UUID?
        var offset = CGSize.zero
        var startCenter = CGPoint.zero
        var startDial: Int?
        var snappedBack = false
    }

    private var grips: [Int: Grip] = [:]
    @ObservationIgnored private var hasLaidOut = false
    private var mouseGrip: (id: UUID, startCenter: CGPoint)?

    init() {
        resetLayout()
    }

    func resetLayout() {
        grips = [:]
        mergeCandidates = []
        cards = [
            Card(center: CGPoint(x: canvasSize.width * 0.40, y: canvasSize.height * 0.34), kind: .loan(.demo)),
            Card(center: CGPoint(x: canvasSize.width * 0.58, y: canvasSize.height - 215), kind: .temperatures),
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

    func isHeld(_ cardID: UUID) -> Bool {
        heldIDs.contains(cardID)
    }

    private var heldIDs: Set<UUID> {
        Set(grips.values.compactMap(\.cardID) + [mouseGrip?.id].compactMap { $0 })
    }

    // MARK: Hands

    func point(for hand: TrackedHand) -> CGPoint {
        point(fromCanvasUnits: hand.cursor)
    }

    func cursorState(for hand: TrackedHand) -> HandCursor.Mode {
        if hand.isFist { return .talking }
        guard hand.isPinching else {
            return cards.contains { $0.frame.contains(point(for: hand)) } ? .overCard : .open
        }
        if hand.pinch == .twist, let id = grips[hand.id]?.cardID, let dial = card(id)?.dial {
            return .twist(fraction: dial.fraction, label: dial.label)
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
            if let swipe = hand.swipe {
                toggleStyle(at: point(fromCanvasUnits: swipe.origin))
            }
            track(hand)
        }
        hands = newHands
        updateMerges()
        updateTrash()
    }

    private func track(_ hand: TrackedHand) {
        guard hand.isPinching else {
            release(hand.id)
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
                    startDial: card.dial?.value
                )
            } else {
                grips[hand.id] = Grip()
            }
        }

        guard var grip = grips[hand.id], let id = grip.cardID, let index = index(of: id) else { return }

        if hand.pinch == .twist {
            // The card followed the hand while the pinch was undecided; a twist puts it back.
            if !grip.snappedBack {
                cards[index].center = grip.startCenter
                grip.snappedBack = true
                grips[hand.id] = grip
            }
            if let start = grip.startDial, let dial = cards[index].dial {
                let steps = Int((hand.twist * 180 / .pi / degreesPerStep).rounded())
                cards[index].setDial(start + steps * dial.step)
            }
        } else {
            cards[index].center = clamped(CGPoint(x: p.x + grip.offset.width, y: p.y + grip.offset.height))
        }
    }

    // MARK: Push together

    /// Lights up a dealer loan and a quote pushed into each other, and merges them once they
    /// overlap enough. Two cards of the same kind never merge: there'd be nothing to compare.
    private func updateMerges() {
        var candidates: Set<UUID> = []
        for id in heldIDs {
            guard let moving = card(id), let movingRole = moving.loanCard?.role else { continue }
            for other in cards where other.id != id {
                guard let otherRole = other.loanCard?.role, otherRole != movingRole else { continue }
                let overlap = overlapRatio(moving.frame, other.frame)
                if overlap >= Self.mergeOverlap {
                    merge(id, other.id)
                    return
                }
                if overlap >= Self.candidateOverlap {
                    candidates.formUnion([id, other.id])
                }
            }
        }
        if candidates != mergeCandidates { mergeCandidates = candidates }
    }

    /// Replaces the dealer's loan card and a quote card with one comparison.
    func merge(_ first: UUID, _ second: UUID) {
        guard let a = card(first), let b = card(second),
              let loanA = a.loanCard, let loanB = b.loanCard, loanA.role != loanB.role else { return }
        let (dealer, other) = loanA.role == .dealer ? (loanA, loanB) : (loanB, loanA)

        var comparison = Comparison(dealer: dealer, other: other)
        comparison.other.loan.termMonths = dealer.loan.termMonths
        let center = CGPoint(x: (a.center.x + b.center.x) / 2, y: (a.center.y + b.center.y) / 2)

        // Hands still pinching keep pinching, but hold nothing until they let go.
        for (hand, grip) in grips where grip.cardID == first || grip.cardID == second {
            grips[hand] = Grip()
        }
        mouseGrip = nil
        mergeCandidates = []
        let merged = Card(center: clamped(center), kind: .comparison(comparison))
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) {
            cards.removeAll { $0.id == first || $0.id == second }
            cards.append(merged)
        }
        settle(merged.id)
    }

    /// Merges the dealer's card with a quote, for when hands aren't handy.
    /// Returns false unless there's one of each.
    @discardableResult
    func compareLoans() -> Bool {
        guard let dealer = cards.last(where: { $0.loanCard?.role == .dealer }),
              let quote = cards.last(where: { $0.loanCard?.role == .quote }) else { return false }
        merge(dealer.id, quote.id)
        return true
    }

    // MARK: Trash

    /// Where the trash sits; it shows while a card is held. Drop a card on it to delete it.
    var trashCenter: CGPoint { CGPoint(x: canvasSize.width - 80, y: canvasSize.height - 80) }
    static let trashRadius = 110.0

    var isTrashVisible: Bool { !heldIDs.isEmpty }
    /// The held card that's over the trash, which letting go deletes.
    private(set) var trashTarget: UUID?

    private func updateTrash() {
        let over = heldIDs.first { id in
            card(id).map { hypot($0.center.x - trashCenter.x, $0.center.y - trashCenter.y) < Self.trashRadius } ?? false
        }
        if over != trashTarget { trashTarget = over }
    }

    /// A pinch let go: deletes the card if it was over the trash.
    private func release(_ handID: Int) {
        if let id = grips[handID]?.cardID, id == trashTarget {
            delete(id)
        }
        grips[handID] = nil
    }

    func delete(_ id: UUID) {
        for (hand, grip) in grips where grip.cardID == id {
            grips[hand] = Grip()
        }
        if trashTarget == id { trashTarget = nil }
        withAnimation(.spring(duration: 0.3)) {
            cards.removeAll { $0.id == id }
        }
    }

    /// Deletes the frontmost card, for the Delete key and voice.
    @discardableResult
    func deleteFrontCard() -> Bool {
        guard let card = cards.last else { return false }
        delete(card.id)
        return true
    }

    func clearCanvas() {
        grips = grips.mapValues { _ in Grip() }
        mergeCandidates = []
        trashTarget = nil
        withAnimation(.spring(duration: 0.35)) {
            cards.removeAll()
        }
    }

    // MARK: Swipe

    func toggleStyle(of id: UUID) {
        guard let index = index(of: id) else { return }
        withAnimation(.spring(duration: 0.35)) {
            cards[index].style.toggle()
        }
    }

    /// Flips the card under `point`, or the frontmost card.
    private func toggleStyle(at point: CGPoint) {
        guard let card = cards.last(where: { $0.frame.contains(point) }) ?? cards.last else { return }
        toggleStyle(of: card.id)
    }

    func toggleFrontStyle() {
        guard let card = cards.last else { return }
        toggleStyle(of: card.id)
    }

    // MARK: Scans

    /// A photo lands on the canvas, flying in from the phone panel, while it is read.
    @discardableResult
    func addScan(_ image: NSImage) -> UUID {
        var card = Card(center: CGPoint(x: canvasSize.width - 160, y: 140), kind: .scan(Scan(image: image, status: .reading)))
        card.isArriving = true
        let target = freeSpot(for: card.size)
        let id = card.id
        withAnimation(.spring(duration: 0.25)) {
            cards.append(card)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            self?.moveCard(id, to: target)
            try? await Task.sleep(for: .milliseconds(900))
            if let index = self?.index(of: id) { self?.cards[index].isArriving = false }
        }
        return id
    }

    /// Turns a read scan into what it shows: a contract or quote becomes a loan card;
    /// anything else stays a photo with what was found on it.
    func finishScan(_ id: UUID, with reading: OfferReading) {
        guard let index = index(of: id) else { return }
        let dealer = dealerLoan

        switch reading.documentType {
        case .loanContract:
            guard let loan = reading.loan else { break }
            let card = LoanCard(role: .dealer, loan: loan, pitch: loan, source: "Read from the contract", reading: reading)
            withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
                cards[index].kind = .loan(card)
                // One dealer card: a new contract (or the same one again) replaces the old
                // card, and the demo numbers.
                cards.removeAll { $0.id != id && $0.loanCard?.role == .dealer }
            }
            settle(id)
            return
        case .loanQuote:
            guard let apr = reading.aprPercent else { break }
            // A pre-approval rarely states an amount or term, so borrow the dealer's
            // to compare like for like.
            let principal = dealer?.loan.principal ?? reading.amountFinanced ?? LoanTerms.demoContract.principal
            let term = dealer?.loan.termMonths ?? reading.termMonths ?? 48
            let loan = LoanTerms(principal: principal, apr: apr / 100, termMonths: term)
            let source = dealer == nil ? "Read from the quote" : "Rate from the quote · amount and term from the contract"
            let card = LoanCard(role: .quote, loan: loan, pitch: dealer?.pitch ?? loan, source: source, reading: reading)
            withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
                cards[index].kind = .loan(card)
                // One quote card, like one dealer card.
                cards.removeAll { $0.id != id && $0.loanCard?.role == .quote }
            }
            settle(id)
            return
        case .windowSticker:
            break
        case .other:
            // Usually a stray capture (the phone pointed at the room): show it briefly, then clear it.
            setScanStatus(at: index, .read(reading))
            removeLater(id)
            return
        }
        setScanStatus(at: index, .read(reading))
    }

    func failScan(_ id: UUID, message: String) {
        guard let index = index(of: id) else { return }
        setScanStatus(at: index, .failed(message))
        removeLater(id, after: .seconds(8))
    }

    private func removeLater(_ id: UUID, after delay: Duration = .seconds(4)) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !isHeld(id) else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self.cards.removeAll { $0.id == id }
            }
        }
    }

    private func setScanStatus(at index: Int, _ status: Scan.Status) {
        guard case .scan(var scan) = cards[index].kind else { return }
        scan.status = status
        withAnimation(.spring(duration: 0.4)) {
            cards[index].kind = .scan(scan)
        }
        settle(cards[index].id)
    }

    /// A card that grew (a scan becoming a chart) moves to open space if it now covers
    /// another card or a panel.
    private func settle(_ id: UUID) {
        guard let index = index(of: id) else { return }
        let frame = cards[index].frame
        let others = cards.filter { $0.id != id }.map(\.frame) + reservedAreas
        guard others.contains(where: { $0.intersects(frame) }) else { return }
        cards[index].center = freeSpot(for: cards[index].size, excluding: id)
    }

    /// The dealer's loan as it stands now, from its own card or a comparison.
    private var dealerLoan: LoanCard? {
        for card in cards.reversed() {
            switch card.kind {
            case .loan(let loan) where loan.role == .dealer: return loan
            case .comparison(let comparison): return comparison.dealer
            default: continue
            }
        }
        return nil
    }

    /// A credit union pre-approval at 6.4% for the dealer's amount and term, for rehearsing
    /// the comparison without the printed quote.
    func addDemoQuote() {
        let dealer = dealerLoan ?? .demo
        let loan = dealer.loan.with(apr: 0.064)
        let card = Card(center: .zero, kind: .loan(LoanCard(role: .quote, loan: loan, pitch: dealer.pitch, source: "Demo quote: 6.4% pre-approval", reading: nil)))
        var placed = card
        placed.center = freeSpot(for: card.size)
        withAnimation(.spring(duration: 0.4, bounce: 0.25)) {
            cards.append(placed)
        }
    }

    // MARK: Money

    /// The deal as the canvas shows it: the dealer's loan at the term on screen, any quote,
    /// the contract it was read from and any window stickers. Nil without a dealer loan.
    func moneyFacts(pitchChecks: [PitchCheck] = []) -> MoneyFacts? {
        var dealer: LoanCard?
        var quote: LoanTerms?
        for card in cards {
            switch card.kind {
            case .loan(let loan) where loan.role == .dealer: dealer = loan
            case .loan(let loan) where loan.role == .quote: quote = loan.loan
            case .comparison(let comparison):
                dealer = comparison.dealer
                quote = comparison.other.loan
            default: break
            }
        }
        guard let dealer else { return nil }
        let stickers = cards.compactMap { card -> OfferReading? in
            if case .scan(let scan) = card.kind, case .read(let reading) = scan.status, reading.documentType == .windowSticker {
                return reading
            }
            return nil
        }
        return MoneyFacts(
            pitch: dealer.pitch,
            chosen: dealer.loan,
            quote: quote?.with(termMonths: dealer.loan.termMonths),
            contract: dealer.reading,
            stickers: stickers,
            pitchChecks: pitchChecks
        )
    }

    /// Shows advice in its card, adding the card if there isn't one.
    func showAdvice(_ advice: Advice) {
        show(.advice(advice)) { if case .advice = $0 { true } else { false } }
    }

    /// Shows the checks in the pitch card, adding it if there isn't one.
    func showPitchChecks(_ checks: [PitchCheck]) {
        show(.pitch(checks)) { if case .pitch = $0 { true } else { false } }
    }

    private func show(_ kind: Card.Kind, replacing matches: (Card.Kind) -> Bool) {
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
            if let index = cards.firstIndex(where: { matches($0.kind) }) {
                cards[index].kind = kind
                settle(cards[index].id)
            } else {
                var card = Card(center: .zero, kind: kind)
                card.center = freeSpot(for: card.size)
                cards.append(card)
            }
        }
    }

    // MARK: Temperatures

    var showsTemperatures: Bool {
        cards.contains { $0.kind == .temperatures }
    }

    func toggleTemperatures() {
        withAnimation(.spring(duration: 0.35)) {
            if showsTemperatures {
                cards.removeAll { $0.kind == .temperatures }
            } else {
                let card = Card(center: .zero, kind: .temperatures)
                var placed = card
                placed.center = freeSpot(for: card.size)
                cards.append(placed)
            }
        }
    }

    // MARK: Mouse and keyboard

    func mouseDrag(_ id: UUID, translation: CGSize) {
        guard let index = index(of: id) else { return }
        if mouseGrip?.id != id {
            mouseGrip = (id, cards[index].center)
            let card = cards.remove(at: index)
            cards.append(card)
        }
        guard let start = mouseGrip, let index = self.index(of: id) else { return }
        cards[index].center = clamped(CGPoint(x: start.startCenter.x + translation.width, y: start.startCenter.y + translation.height))
        updateMerges()
        updateTrash()
    }

    func endMouseDrag() {
        if let id = mouseGrip?.id, id == trashTarget {
            delete(id)
        }
        mouseGrip = nil
        mergeCandidates = []
        trashTarget = nil
    }

    /// Turns the frontmost card's dial by whole steps.
    func stepDial(by steps: Int) {
        guard let index = cards.lastIndex(where: { $0.dial != nil }), let dial = cards[index].dial else { return }
        cards[index].setDial(dial.value + steps * dial.step)
    }

    /// Sets the term on the frontmost loan or comparison, for voice.
    @discardableResult
    func setTerm(_ months: Int) -> Int? {
        guard let index = cards.lastIndex(where: { $0.dial != nil }) else { return nil }
        cards[index].setDial(months)
        return cards[index].dial?.value
    }

    /// Sets the APR on the frontmost loan card, for voice. Returns false when there is none.
    @discardableResult
    func setRate(_ aprPercent: Double) -> Bool {
        guard let index = cards.lastIndex(where: { $0.loanCard != nil }),
              case .loan(var card) = cards[index].kind else { return false }
        card.loan.apr = aprPercent / 100
        cards[index].kind = .loan(card)
        return true
    }

    /// What's on the canvas, in words, so voice commands like "make it shorter" have a referent.
    var voiceContext: String {
        let parts = cards.map { card -> String in
            switch card.kind {
            case .loan(let loan):
                "\(loan.title): \(dollars(loan.loan.principal)) at \(loan.loan.apr.formatted(.percent.precision(.fractionLength(1)))) for \(loan.loan.termMonths) months"
            case .comparison(let comparison):
                "Dealer and credit union compared at \(comparison.termMonths) months"
            case .temperatures:
                "Live cup temperatures"
            case .scan:
                "A photo being read"
            case .advice:
                "What to say to the dealer"
            case .pitch:
                "The salesperson's pitch, checked"
            }
        }
        return parts.isEmpty ? "Nothing yet." : parts.joined(separator: ". ") + "."
    }

    // MARK: Layout

    func card(_ id: UUID) -> Card? {
        cards.first { $0.id == id }
    }

    private func index(of id: UUID) -> Int? {
        cards.firstIndex { $0.id == id }
    }

    private func moveCard(_ id: UUID, to center: CGPoint) {
        guard let index = index(of: id) else { return }
        cards[index].center = center
    }

    private func point(fromCanvasUnits unit: CGPoint) -> CGPoint {
        CGPoint(x: unit.x * canvasSize.width, y: unit.y * canvasSize.height)
    }

    /// Keeps at least a third of a card on the canvas.
    private func clamped(_ center: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(center.x, 80), canvasSize.width - 80),
            y: min(max(center.y, 60), canvasSize.height - 60)
        )
    }

    /// Where the overlays sit: the header, the phone and paper panels, the voice bar and the
    /// hand debug panel.
    private var reservedAreas: [CGRect] {
        var areas = [
            CGRect(x: 0, y: 0, width: 420, height: 110),
            CGRect(x: canvasSize.width - 320, y: 0, width: 320, height: 560),
            CGRect(x: canvasSize.width / 2 - 260, y: canvasSize.height - 75, width: 520, height: 75),
            CGRect(x: canvasSize.width - 170, y: canvasSize.height - 170, width: 170, height: 170),
        ]
        if showDebug {
            areas.append(CGRect(x: 0, y: canvasSize.height - 480, width: 384, height: 480))
        }
        return areas
    }

    /// The spot that overlaps the least, nearest the middle among equals. Covering a panel
    /// (header, phone, debug, trash, voice bar) costs three times as much as covering a card.
    private func freeSpot(for size: CGSize, excluding excluded: UUID? = nil) -> CGPoint {
        let others = cards.filter { !$0.isArriving && $0.id != excluded }.map(\.frame)
        let reserved = reservedAreas
        let middle = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        var best = middle
        var bestScore = Double.infinity
        let minX = size.width / 2 + 20, maxX = canvasSize.width - size.width / 2 - 20
        let minY = size.height / 2 + 20, maxY = canvasSize.height - size.height / 2 - 20
        guard minX <= maxX, minY <= maxY else { return clamped(middle) }

        func covered(_ rect: CGRect, by areas: [CGRect]) -> Double {
            areas.reduce(0.0) { total, other in
                let shared = rect.intersection(other)
                return shared.isNull ? total : total + shared.width * shared.height
            }
        }
        for y in stride(from: minY, through: maxY, by: 20) {
            for x in stride(from: minX, through: maxX, by: 20) {
                let rect = CGRect(x: x - size.width / 2, y: y - size.height / 2, width: size.width, height: size.height)
                let score = covered(rect, by: others) + 3 * covered(rect, by: reserved) + hypot(x - middle.x, y - middle.y) * 2
                if score < bestScore {
                    bestScore = score
                    best = CGPoint(x: x, y: y)
                }
            }
        }
        return best
    }

    /// How much of the smaller rectangle the two share, 0...1.
    private func overlapRatio(_ a: CGRect, _ b: CGRect) -> Double {
        let shared = a.intersection(b)
        guard !shared.isNull else { return 0 }
        let smaller = min(a.width * a.height, b.width * b.height)
        return smaller > 0 ? shared.width * shared.height / smaller : 0
    }
}
