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

    /// The coordinate space cards and hover targets are measured in.
    static let space = "canvas"
    /// Every page read so far, so any number on the canvas can show where it came from.
    var documents: [UUID: PageDocument] = [:]
    /// How far down the phone and paper panels reach, top right.
    var panelHeight = 560.0
    /// The card being worked on: the last one scanned, grabbed or clicked. Questions and
    /// commands go to it.
    private(set) var focusedID: UUID?
    /// The last page in focus: what answers, notes and models sit beside.
    @ObservationIgnored private var pageInFocus: UUID?
    /// Folded cards, in the order they were folded.
    @ObservationIgnored private var chipOrder: [UUID] = []
    /// The group of the card in focus; every other group is folded.
    @ObservationIgnored private var groupInFocus: UUID?
    /// The groups of chips down the left edge, for drawing a tray behind each.
    private(set) var chipTrays: [ChipTray] = []
    /// What's being hovered, by mouse or by a hand held still over it.
    private(set) var hovered: HoverTarget?
    /// Called when the hovered item changes, for lighting the same spot on the phone.
    @ObservationIgnored var onHoverChange: ((HoverTarget?) -> Void)?
    @ObservationIgnored private var hoverFrames: [HoverTarget: CGRect] = [:]
    @ObservationIgnored private var handHover: (target: HoverTarget, since: Date)?
    @ObservationIgnored private var hoveredByHand = false

    /// What a pinching hand grabbed when the pinch began. `cardID` is nil for empty canvas.
    private struct Grip {
        var cardID: UUID?
        var offset = CGSize.zero
        var startCenter = CGPoint.zero
        var startDial: Int?
        var snappedBack = false
    }

    private var grips: [Int: Grip] = [:]
    private var mouseGrip: (id: UUID, startCenter: CGPoint)?

    /// The canvas starts empty: hand Grasp anything. ⌘R lays out the demo cards.
    init() {}

    /// The demo layout: the car loan and the cup temperatures.
    func resetLayout() {
        grips = [:]
        mergeCandidates = []
        focusedID = nil
        pageInFocus = nil
        groupInFocus = Self.carDeal
        chipOrder = []
        chipTrays = []
        cards = [
            Card(center: CGPoint(x: canvasSize.width * 0.40, y: canvasSize.height * 0.34), kind: .loan(.demo)),
            Card(center: CGPoint(x: canvasSize.width * 0.58, y: canvasSize.height - 215), kind: .temperatures),
        ]
    }

    func setCanvasSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        canvasSize = size
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
        updateHandHover()
    }

    private func track(_ hand: TrackedHand) {
        guard hand.isPinching else {
            release(hand.id)
            return
        }
        let p = point(for: hand)

        if grips[hand.id] == nil {
            // A pinch grabs the top card under it, or nothing; it never picks one up later.
            // Grabbing puts it in focus, and a chip opens up under the hand.
            if let found = cards.last(where: { $0.frame.contains(p) }) {
                focus(found.id, openingAt: p)
                guard let card = cards.last else { return }
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
            guard let moving = card(id) else { continue }
            for other in cards where other.id != id {
                guard Self.canMerge(moving, other) else { continue }
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

    /// A dealer loan and a quote compare; so do a paper's model and the cups on the bench.
    private static func canMerge(_ a: Card, _ b: Card) -> Bool {
        if let roleA = a.loanCard?.role, let roleB = b.loanCard?.role { return roleA != roleB }
        switch (a.kind, b.kind) {
        case (.model(let model), .temperatures), (.temperatures, .model(let model)): return !model.comparesCups
        default: return false
        }
    }

    /// Replaces the dealer's loan card and a quote card with one comparison, or folds the cup
    /// chart into a paper's model so your cups run against its prediction.
    func merge(_ first: UUID, _ second: UUID) {
        if let pair = [first, second].first(where: { if case .model = card($0)?.kind { true } else { false } }),
           let cups = [first, second].first(where: { if case .temperatures = card($0)?.kind { true } else { false } }) {
            for (hand, grip) in grips where grip.cardID == first || grip.cardID == second {
                grips[hand] = Grip()
            }
            mouseGrip = nil
            mergeCandidates = []
            withAnimation(.spring(duration: 0.45, bounce: 0.3)) {
                cards.removeAll { $0.id == cups }
                if let index = index(of: pair), case .model(var model) = cards[index].kind {
                    model.comparesCups = true
                    cards[index].kind = .model(model)
                }
            }
            settle(pair)
            return
        }
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
        layoutChips()
        // Throwing away the page in focus opens the one read before it.
        if focusedID == id || pageInFocus == id {
            focusedID = nil
            pageInFocus = nil
            if let previous = pagesByAge.last { focus(previous.id) }
        }
    }

    /// Deletes the card in focus (or the frontmost), for the Delete key and voice.
    @discardableResult
    func deleteFocusedCard() -> Bool {
        guard let id = focusedID ?? cards.last?.id else { return false }
        delete(id)
        return true
    }

    func clearCanvas() {
        grips = grips.mapValues { _ in Grip() }
        mergeCandidates = []
        trashTarget = nil
        focusedID = nil
        pageInFocus = nil
        groupInFocus = nil
        chipOrder = []
        withAnimation(.spring(duration: 0.35)) {
            cards.removeAll()
            chipTrays = []
        }
    }

    // MARK: Focus

    /// The group the car deal's cards share: the loans, the stickers, what to say.
    static let carDeal = UUID()

    /// Moves focus to a card and brings it to the front. Focusing a card from another group
    /// brings that group back (its pages where they were, and the last thing beside them) and
    /// folds everything else into chips down the left edge, a group to each page. A chip that
    /// gets focus opens again: at `point` (under a hand that grabbed it), beside its page, or
    /// where it was before it folded.
    func focus(_ id: UUID, openingAt point: CGPoint? = nil) {
        guard let card = card(id) else { return }
        let group = group(of: card)
        let switching = folds(card) && group != groupInFocus
        focusedID = id
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
            if switching {
                groupInFocus = group
                for other in cards where other.id != id && !other.isFolded && folds(other) && self.group(of: other) != group {
                    fold(other.id)
                }
                // The group's pages come back together (the car deal's loans and stickers), and
                // a chip from beside a page brings that page back with it.
                pageInFocus = pageCard(of: group)
                for other in cards where other.isFolded && other.kind.isPage && self.group(of: other) == group {
                    open(other.id, at: nil)
                }
            }
            let head = isHead(card)
            if head {
                pageInFocus = id
                open(id, at: point)
            } else if card.isFolded {
                if card.kind.sitsBeside, point == nil { dock(id) } else { open(id, at: point) }
            }
            if switching, head, let last = chipOrder.last(where: { chip in
                self.card(chip).map { $0.kind.sitsBeside && self.group(of: $0) == group } ?? false
            }) {
                dock(last)
            }
        }
        if let index = index(of: id) {
            let card = cards.remove(at: index)
            cards.append(card)
        }
    }

    /// Page cards, oldest first.
    private var pagesByAge: [Card] {
        let pages: [(card: Card, readAt: Date)] = cards.compactMap { card in
            guard case .document(let document) = card.kind else { return nil }
            return (card, document.readAt)
        }
        return pages.sorted { $0.readAt < $1.readAt }.map(\.card)
    }

    /// The group a card folds into: its own page's, the car deal's, or its own.
    func group(of card: Card) -> UUID {
        switch card.kind {
        case .loan, .comparison, .advice, .pitch:
            return Self.carDeal
        case .scan(let scan):
            if case .read(let reading) = scan.status, reading.documentType != .other { return Self.carDeal }
            return card.id
        default:
            break
        }
        if card.kind.sitsBeside, let page = owner(of: card).flatMap(self.card), page.id != card.id {
            return group(of: page)
        }
        return card.id
    }

    /// The page a card sits beside: the paper its notes, model or method are about, the bill a
    /// letter disputes, or the card in focus when a question was asked.
    private func owner(of card: Card) -> UUID? {
        if case .answer(let answer) = card.kind { return answer.pageID.flatMap { self.card($0)?.id } }
        let documentID: UUID? = switch card.kind {
        case .notes(let notes): notes.paperID
        case .model(let model): model.paperID
        case .method(let method): method.paperID
        case .related(let related): related.paperID
        case .letter(let letter): letter.documentID
        case .guide(let guide): guide.documentID
        default: nil
        }
        return documentID.flatMap { id in cards.first { document(for: $0)?.id == id }?.id }
    }

    /// The first card of a group: a page, or a card beside nothing.
    private func isHead(_ card: Card) -> Bool {
        card.kind.isPage || (card.kind.sitsBeside && owner(of: card) == nil)
    }

    /// The card a group's chips sit beside: its newest page, or the card heading it.
    private func pageCard(of group: UUID) -> UUID? {
        (cards.last { $0.kind.isPage && self.group(of: $0) == group } ?? cards.last { isHead($0) && self.group(of: $0) == group })?.id
    }

    /// Live cards (the cup temperatures) and photos still being read stay where they are.
    private func folds(_ card: Card) -> Bool {
        switch card.kind {
        case .temperatures: false
        case .scan(let scan): if case .read(let reading) = scan.status { reading.documentType != .other } else { false }
        default: !isHeld(card.id)
        }
    }

    private func open(_ id: UUID, at point: CGPoint?) {
        guard let index = index(of: id), cards[index].isFolded else { return }
        cards[index].isFolded = false
        chipOrder.removeAll { $0 == id }
        let size = cards[index].size
        if let point {
            cards[index].center = fitted(point, size: size)
        } else if let back = cards[index].openCenter, isClear(CGRect(x: back.x - size.width / 2, y: back.y - size.height / 2, width: size.width, height: size.height), excluding: id) {
            cards[index].center = back
        } else {
            cards[index].center = freeSpot(for: size, excluding: id)
        }
        layoutChips()
    }

    /// Shrinks a card to a chip in its group down the left edge.
    private func fold(_ id: UUID) {
        guard let index = index(of: id), !cards[index].isFolded else { return }
        cards[index].openCenter = cards[index].center
        cards[index].isFolded = true
        if !chipOrder.contains(id) { chipOrder.append(id) }
        layoutChips()
    }

    /// Chips down the left edge, a group at a time in the order they folded: a page (or the car
    /// deal) on top, then what sat beside it, indented. A group that doesn't fit starts a new column.
    private func layoutChips() {
        chipOrder.removeAll { id in !cards.contains { $0.id == id && $0.isFolded } }
        var groups: [(key: UUID, ids: [UUID])] = []
        for id in chipOrder {
            guard let card = card(id) else { continue }
            let key = group(of: card)
            if let at = groups.firstIndex(where: { $0.key == key }) { groups[at].ids.append(id) } else { groups.append((key, [id])) }
        }
        let top: CGFloat = 130, gap: CGFloat = 6, pad: CGFloat = 8, groupGap: CGFloat = 18
        let bottom = canvasSize.height - (showDebug ? Self.debugPanelHeight + 10 : 90)
        var x: CGFloat = 28, y = top
        var trays: [ChipTray] = []
        for group in groups {
            let ids = group.ids.filter { card($0)?.kind.isPage == true } + group.ids.filter { card($0)?.kind.isPage != true }
            let caption = group.key == Self.carDeal ? "Car deal" : nil
            let trayed = ids.count > 1 || caption != nil || group.key == groupInFocus
            var height = gap * CGFloat(ids.count - 1) + (caption == nil ? 0 : ChipTray.captionHeight)
            for id in ids { height += card(id)?.size.height ?? 0 }
            if y > top, y + height > bottom {
                x += Card.chipSize.width + 2 * pad + 14
                y = top
            }
            if caption != nil { y += ChipTray.captionHeight }
            var frames: [CGRect] = []
            for id in ids {
                guard let index = index(of: id) else { continue }
                let size = cards[index].size
                cards[index].center = CGPoint(x: x + Card.chipSize.width - size.width / 2, y: y + size.height / 2)
                frames.append(cards[index].frame)
                y += size.height + gap
            }
            if trayed, let first = frames.first {
                var frame = frames.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -pad, dy: -pad)
                if caption != nil {
                    frame.origin.y -= ChipTray.captionHeight
                    frame.size.height += ChipTray.captionHeight
                }
                trays.append(ChipTray(id: group.key, frame: frame, caption: caption, isInFocus: group.key == groupInFocus))
            }
            y += groupGap - gap
        }
        chipTrays = trays
        // Nothing open sits under the chips: a card there moves to open space.
        let column = chipColumn
        for card in cards where !card.isFolded && folds(card) && card.id != focusedID && card.id != mouseGrip?.id
            && column.contains(where: { $0.intersects(card.frame) }) {
            moveCard(card.id, to: freeSpot(for: card.size, excluding: card.id))
        }
    }

    /// The chips and their trays.
    private var chipColumn: [CGRect] {
        chipTrays.map(\.frame) + cards.filter(\.isFolded).map(\.frame)
    }

    /// Where open cards can start, right of the chips.
    private var leftOfChips: CGFloat {
        (chipColumn.map(\.maxX).max() ?? 0) + 20
    }

    /// True when a card could sit here without covering a chip, a panel or another open card.
    private func isClear(_ rect: CGRect, excluding excluded: UUID) -> Bool {
        let fits = rect.minX >= 0 && rect.minY >= 0 && rect.maxX <= canvasSize.width && rect.maxY <= canvasSize.height
        let others = cards.filter { $0.id != excluded && !$0.isFolded }.map(\.frame)
        return fits && !(chipColumn + reservedAreas + others).contains { $0.intersects(rect) }
    }

    /// The page in focus, or the page last in focus when focus is on something beside it.
    var focusedDocument: PageDocument? {
        pageInFocus.flatMap(card).flatMap(document(for:))
    }

    // MARK: Swipe

    func toggleStyle(of id: UUID) {
        guard let index = index(of: id) else { return }
        withAnimation(.spring(duration: 0.35)) {
            // A swipe across a paper's model flips to its next condition: lid on, lid off.
            if case .model(var model) = cards[index].kind {
                model.selected = (model.selected + 1) % model.model.conditions.count
                model.twistedK = nil
                cards[index].kind = .model(model)
            } else {
                cards[index].style.toggle()
            }
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
            focus(id)
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
            focus(id)
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
        focus(placed.id)
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
        if let id = cards.first(where: { if case .advice = $0.kind { true } else { false } })?.id { focus(id) }
    }

    /// Shows the checks in the pitch card, adding it if there isn't one.
    func showPitchChecks(_ checks: [PitchCheck]) {
        show(.pitch(checks)) { if case .pitch = $0 { true } else { false } }
        if let id = cards.first(where: { if case .pitch = $0.kind { true } else { false } })?.id { focus(id) }
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
            focus(id, openingAt: cards[index].center)
            guard let card = cards.last else { return }
            mouseGrip = (id, card.center)
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
            case .scan(let scan):
                if case .read(let reading) = scan.status, reading.documentType == .windowSticker {
                    "A window sticker, add-ons " + reading.addOns.map { "\($0.name) \(dollars($0.amount))" }.joined(separator: ", ")
                } else {
                    "A photo being read"
                }
            case .advice:
                "What to say to the dealer"
            case .pitch:
                "The salesperson's pitch, checked"
            case .document(let document):
                "\(document.reading.title) (\(document.reading.kind))\(card.id == pageInFocus ? ", in focus" : "")"
            case .answer(let answer):
                "An answer to “\(answer.question)”"
            case .notes(let notes):
                "Notes on \(notes.paperTitle): \(notes.linked.notes.count) notes, "
                    + "\(notes.linked.notes.filter { $0.status == .differs }.count) differ from the paper"
            case .notebook(let notebook):
                "Lab notebook: \(notebook.notebook.title)"
            case .guide(let guide):
                "The protocol \(guide.lab.title), \(guide.lab.steps.count) steps, ready to guide"
            case .letter(let letter):
                "A dispute letter to \(letter.letter.company) asking for \(dollars(letter.letter.total, cents: true)): "
                    + letter.letter.items.map { "\($0.title) \(dollars($0.amount, cents: true))" }.joined(separator: "; ")
            case .related(let related):
                "Related work for \(related.paperTitle): " + related.result.related.map { "\($0.work.shortName), \($0.work.title)" }.joined(separator: "; ")
                    + ". Directions: " + related.result.directions.map { "\($0.title) (\($0.verdict.rawValue))" }.joined(separator: "; ")
            case .method(let method):
                "The method of \(method.paperTitle): varied \(method.map.varied.map(\.name).joined(separator: ", ")); "
                    + "not controlled \(method.map.notControlled.map(\.name).joined(separator: ", "))"
            case .model(let model):
                "The model from \(model.paperTitle), running, on \(model.condition.name)"
                    + (model.model.mismatches.isEmpty ? "" : "; \(model.model.mismatches.count) of its reported results don't follow from its own equation")
            }
        }
        return parts.isEmpty ? "Nothing yet." : parts.joined(separator: ". ") + "."
    }

    // MARK: Layout

    func card(_ id: UUID) -> Card? {
        cards.first { $0.id == id }
    }

    func index(of id: UUID) -> Int? {
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

    /// Moves a center so the whole card is on the canvas.
    private func fitted(_ center: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(center.x, size.width / 2 + 20), max(size.width / 2 + 20, canvasSize.width - size.width / 2 - 20)),
            y: min(max(center.y, size.height / 2 + 20), max(size.height / 2 + 20, canvasSize.height - size.height / 2 - 20))
        )
    }

    /// How far up the hand debug panel reaches from the bottom left, with its margin.
    static let debugPanelHeight: CGFloat = 360

    /// Where the overlays sit: the header, the phone and paper panels, the voice bar and the
    /// hand debug panel.
    private var reservedAreas: [CGRect] {
        var areas = [
            CGRect(x: 0, y: 0, width: 420, height: 110),
            CGRect(x: canvasSize.width - 320, y: 0, width: 320, height: panelHeight),
            CGRect(x: canvasSize.width / 2 - 260, y: canvasSize.height - 75, width: 520, height: 75),
            CGRect(x: canvasSize.width - 170, y: canvasSize.height - 170, width: 170, height: 170),
        ]
        if showDebug {
            areas.append(CGRect(x: 0, y: canvasSize.height - Self.debugPanelHeight, width: 384, height: Self.debugPanelHeight))
        }
        return areas
    }

    /// The spot that overlaps the least, nearest the middle among equals. Covering a panel
    /// (header, phone, debug, trash, voice bar) costs three times as much as covering a card.
    private func freeSpot(for size: CGSize, excluding excluded: UUID? = nil) -> CGPoint {
        let placed = cards.filter { !$0.isArriving && $0.id != excluded }
        // Covering the card in focus or a chip costs as much as covering a panel.
        let inFocus = [focusedID, pageInFocus]
        let others = placed.filter { !inFocus.contains($0.id) && !$0.isFolded }.map(\.frame)
        let reserved = reservedAreas + chipTrays.map(\.frame) + placed.filter { inFocus.contains($0.id) || $0.isFolded }.map(\.frame)
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

// MARK: - Where things come from

extension CanvasModel {
    func setHoverFrame(_ target: HoverTarget, _ frame: CGRect) {
        hoverFrames[target] = frame
    }

    func removeHoverFrame(_ target: HoverTarget) {
        hoverFrames[target] = nil
        if hovered == target { setHovered(nil, byHand: false) }
    }

    func hoverFrame(_ target: HoverTarget) -> CGRect? {
        hoverFrames[target]
    }

    func mouseHover(_ target: HoverTarget, inside: Bool) {
        if inside {
            setHovered(target, byHand: false)
        } else if hovered == target, !hoveredByHand {
            setHovered(nil, byHand: false)
        }
    }

    /// An open hand held still over a number for a moment shows where it came from.
    private func updateHandHover() {
        let hand = hands.first { !$0.isPinching && !$0.isFist }
        let point = hand.map { self.point(for: $0) }
        let target = point.flatMap { point in
            hoverFrames
                .filter { $0.value.insetBy(dx: -6, dy: -6).contains(point) }
                .min { $0.value.width * $0.value.height < $1.value.width * $1.value.height }?
                .key
        }
        guard let target else {
            handHover = nil
            if hoveredByHand { setHovered(nil, byHand: false) }
            return
        }
        if handHover?.target == target {
            if let since = handHover?.since, Date().timeIntervalSince(since) >= 0.35 {
                setHovered(target, byHand: true)
            }
        } else {
            handHover = (target, Date())
        }
    }

    private func setHovered(_ target: HoverTarget?, byHand: Bool) {
        hoveredByHand = target != nil && byHand
        guard target != hovered else { return }
        hovered = target
        onHoverChange?(target)
    }

    /// A page has been read: attach it to the card its scan became (a loan card from the car
    /// readers), or turn the scan into a document card. A page with nothing on it is cleared.
    func finishPage(_ cardID: UUID, document: PageDocument) {
        documents[document.id] = document
        guard let index = index(of: cardID) else { return }
        switch cards[index].kind {
        case .loan(var loan):
            loan.documentID = document.id
            cards[index].kind = .loan(loan)
        case .scan(var scan):
            let hasPage = !document.reading.facts.isEmpty || !document.reading.allCatches.isEmpty
            // A window sticker stays a sticker, with its page behind it for questions and hovers;
            // a contract or quote whose terms couldn't be read becomes a page like any other.
            if case .read(let offer) = scan.status, offer.documentType == .windowSticker || !hasPage {
                scan.documentID = document.id
                cards[index].kind = .scan(scan)
                return
            }
            guard hasPage else {
                setScanStatus(at: index, .failed("Nothing to read on this page."))
                removeLater(cardID)
                return
            }
            withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
                cards[index].kind = .document(document)
            }
            focus(cardID)
            settle(cardID)
        default:
            break
        }
    }

    /// The phone capture a hovered fact or catch is on, and a box around it, for the phone to show.
    func phoneSpot(for target: HoverTarget) -> (captureID: UUID, box: LinkHighlight)? {
        switch target {
        case .fact(let documentID, let key):
            guard let document = documents[documentID], let capture = document.captureID,
                  let rect = document.factBoxes[key], let fact = document.reading.fact(key) else { return nil }
            return (capture, LinkHighlight(text: fact.asPrinted, rect: rect, kind: .term))
        case .catchItem(let documentID, let title):
            guard let document = documents[documentID], let capture = document.captureID,
                  let rect = document.catchBoxes[title] else { return nil }
            return (capture, LinkHighlight(text: title, rect: rect, kind: .addon))
        case .answerSource(let cardID, let index):
            guard case .answer(let answer)? = card(cardID)?.kind, answer.sources.indices.contains(index) else { return nil }
            let source = answer.sources[index]
            guard let capture = documents[source.documentID]?.captureID, let rect = source.box else { return nil }
            return (capture, LinkHighlight(text: source.quote, rect: rect, kind: .term))
        case .labStep, .work:
            return nil
        case .cited(let cardID, let index):
            guard let card = card(cardID), let citation = citations(for: card)[safe: index],
                  let document = documents[citation.documentID], let capture = document.captureID,
                  let location = citation.cited.location, let rect = box(for: location, in: document) else { return nil }
            return (capture, LinkHighlight(text: citation.cited.quote, rect: rect, kind: .term))
        case .passage(let cardID, let index):
            guard let (document, passage) = passage(cardID, index), let capture = document.captureID,
                  let rect = box(for: passage.location, in: document) else { return nil }
            return (capture, LinkHighlight(text: passage.quote, rect: rect, kind: .term))
        case .derived:
            return nil
        }
    }

    /// Shows linked notes beside their paper. Notes read from a page take that page's card;
    /// typed notes replace the paper's last notes card.
    func showNotes(_ notes: NotesCard, replacing cardID: UUID? = nil) {
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
            if let cardID, let index = index(of: cardID) {
                cards[index].isFolded = false
                cards[index].kind = .notes(notes)
            } else {
                show(.notes(notes)) { if case .notes(let old) = $0 { old.paperID == notes.paperID } else { false } }
            }
        }
        let notesID = cardID ?? cards.last { if case .notes(let old) = $0.kind { old.paperID == notes.paperID } else { false } }?.id
        guard let notesID, let paper = cards.first(where: { document(for: $0)?.id == notes.paperID }) else { return }
        focus(paper.id)
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) { dock(notesID) }
    }

    /// Shows a paper's model beside the paper, replacing an earlier one for the same paper.
    func showModel(_ model: ModelCard) {
        show(.model(model)) { if case .model(let old) = $0 { old.paperID == model.paperID } else { false } }
        guard let id = cards.last(where: { if case .model(let old) = $0.kind { old.paperID == model.paperID } else { false } })?.id,
              let paper = cards.first(where: { document(for: $0)?.id == model.paperID }) else { return }
        focus(paper.id)
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) { dock(id) }
    }

    /// Picks which of a paper model's conditions the card draws boldest and the dial turns.
    func selectCondition(_ condition: Int, in cardID: UUID) {
        guard let index = index(of: cardID), case .model(var model) = cards[index].kind,
              model.model.conditions.indices.contains(condition) else { return }
        model.selected = condition
        model.twistedK = nil
        withAnimation(.spring(duration: 0.3)) { cards[index].kind = .model(model) }
    }

    /// Runs your cups against the paper's model: the same as pushing the cup chart into it.
    @discardableResult
    func compareCupsWithPaper() -> Bool {
        guard let index = cards.lastIndex(where: { if case .model = $0.kind { true } else { false } }),
              case .model(var model) = cards[index].kind else { return false }
        if let cups = cards.first(where: { if case .temperatures = $0.kind { true } else { false } }) {
            merge(cards[index].id, cups.id)
        } else {
            model.comparesCups = true
            withAnimation(.spring(duration: 0.4)) { cards[index].kind = .model(model) }
            settle(cards[index].id)
        }
        return true
    }

    /// The words on a page a card cites, in the order its hover targets number them.
    func citations(for card: Card) -> [Citation] {
        switch card.kind {
        case .letter(let card):
            return (card.letter.items + card.letter.questions).map { item in
                Citation(documentID: card.documentID, cited: item.cited ?? Cited(quote: "", location: nil),
                         heading: "\(item.title): \(dollars(item.amount, cents: true))", detail: "\(item.reason) (\(item.math))")
            }
        case .related(let related):
            return related.result.directions.map { direction in
                Citation(documentID: related.paperID, cited: direction.cited ?? Cited(quote: "", location: nil),
                         heading: direction.title, detail: direction.note)
            }
        case .method(let method):
            return method.map.items.map { item in
                Citation(documentID: method.paperID, cited: item.cited ?? Cited(quote: "", location: nil), heading: item.name,
                         detail: item.cited == nil ? "Not in the paper: Grasp's suggestion of something to check." : item.detail)
            }
        case .guide(let guide):
            return guide.lab.steps.map { step in
                Citation(documentID: guide.documentID, cited: step.cited, heading: "Step \(step.number): \(step.instruction)",
                         detail: Self.checkWords(step.check))
            }
        case .model(let model):
            let id = model.paperID
            var list = [Citation(documentID: id, cited: model.model.equation, heading: "The paper's equation",
                                 detail: "Swift runs it with the numbers below, each from the page")]
            for condition in model.model.conditions {
                list.append(Citation(documentID: id, cited: condition.k.cited, heading: "\(condition.name): k = \(condition.k.value)",
                                     detail: condition.spread.map { "± \($0) per \(model.model.timeUnit), as printed" }))
            }
            for check in model.model.checks {
                let what = check.reported.kind == .timeTo
                    ? "Time to \(PaperModelText.number(check.reported.at)): the paper says \(PaperModelText.number(check.reported.value.value)) \(model.model.timeUnit)"
                    : "Value at \(PaperModelText.number(check.reported.at)) \(model.model.timeUnit): the paper says \(PaperModelText.number(check.reported.value.value))"
                let detail = check.matches
                    ? "Its own k gives \(PaperModelText.number(check.expected)): it follows."
                    : "Its own k gives \(PaperModelText.number(check.expected)), not \(PaperModelText.number(check.reported.value.value)). One of the two is wrong."
                list.append(Citation(documentID: id, cited: check.reported.value.cited, heading: "\(check.condition) · \(what)", detail: detail))
            }
            return list
        default:
            return []
        }
    }

    /// Shows a paper's method map beside the paper, replacing an earlier one for it.
    func showMethod(_ method: MethodCard) {
        show(.method(method)) { if case .method(let old) = $0 { old.paperID == method.paperID } else { false } }
        guard let id = cards.last(where: { if case .method(let old) = $0.kind { old.paperID == method.paperID } else { false } })?.id,
              let paper = cards.first(where: { document(for: $0)?.id == method.paperID }) else { return }
        focus(paper.id)
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) { dock(id) }
    }

    /// Shows a dispute letter beside its bill, replacing an earlier one for it.
    func showLetter(_ letter: LetterCard) {
        show(.letter(letter)) { if case .letter(let old) = $0 { old.documentID == letter.documentID } else { false } }
        guard let id = cards.last(where: { if case .letter(let old) = $0.kind { old.documentID == letter.documentID } else { false } })?.id,
              let bill = cards.first(where: { document(for: $0)?.id == letter.documentID }) else { return }
        focus(bill.id)
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) { dock(id) }
    }

    /// Shows related work beside the paper, replacing an earlier search for it.
    func showRelated(_ related: RelatedCard) {
        show(.related(related)) { if case .related(let old) = $0 { old.paperID == related.paperID } else { false } }
        guard let id = cards.last(where: { if case .related(let old) = $0.kind { old.paperID == related.paperID } else { false } })?.id,
              let paper = cards.first(where: { document(for: $0)?.id == related.paperID }) else { return }
        focus(paper.id)
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) { dock(id) }
    }

    /// Shows a protocol's steps beside its page, replacing an earlier guide.
    func showGuide(_ guide: GuideCard) {
        show(.guide(guide)) { if case .guide = $0 { true } else { false } }
        guard let id = cards.last(where: { if case .guide = $0.kind { true } else { false } })?.id else { return }
        if let page = cards.first(where: { document(for: $0)?.id == guide.documentID }) { focus(page.id) }
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) { dock(id) }
    }

    /// A guided run takes the canvas: the protocol page and anything beside it fold into chips,
    /// the guide goes left, and the live cups go beside it.
    func layOutGuidedRun() {
        guard let guideID = cards.first(where: { if case .guide = $0.kind { true } else { false } })?.id else { return }
        if !showsTemperatures { toggleTemperatures() }
        withAnimation(.spring(duration: 0.5, bounce: 0.15)) {
            if let guide = card(guideID) { groupInFocus = group(of: guide) }
            for card in cards where card.id != guideID && !card.isFolded && folds(card) {
                fold(card.id)
            }
            let left = leftOfChips
            guard let guide = index(of: guideID) else { return }
            cards[guide].isFolded = false
            chipOrder.removeAll { $0 == guideID }
            let guideSize = cards[guide].size
            cards[guide].center = CGPoint(x: left + guideSize.width / 2, y: 120 + guideSize.height / 2)
            if let cups = cards.firstIndex(where: { $0.kind == .temperatures }) {
                let size = cards[cups].size
                cards[cups].center = CGPoint(x: left + guideSize.width + 20 + size.width / 2, y: panelHeight + 12 + size.height / 2)
            }
            layoutChips()
        }
        focusedID = guideID
    }

    /// How Grasp will know a step is done, in words.
    static func checkWords(_ check: LabProtocol.Step.Check) -> String {
        switch check {
        case .sayDone: "Grasp moves on when you say \u{201C}done\u{201D} or press the button."
        case .rises(let cup): "Grasp watches probe \(cup.rawValue) for the pour."
        case .drops(let cup): "Grasp watches probe \(cup.rawValue) for the drop."
        case .below(let cup, let limit): "Grasp waits until cup \(cup.rawValue) is below \(Int(limit)) °C."
        case .above(let cup, let limit): "Grasp waits until cup \(cup.rawValue) is above \(Int(limit)) °C."
        case .wait(let seconds): "Grasp times \(clockTime(seconds))."
        }
    }

    /// Shows a written-up lab session, replacing the last one.
    func showNotebook(_ notebook: NotebookCard) {
        // The notebook is what's worth reading now: the guide and the other side cards fold away.
        withAnimation(.spring(duration: 0.45)) {
            for card in cards where card.kind.sitsBeside && !card.isFolded {
                if case .notebook = card.kind { continue }
                fold(card.id)
            }
        }
        show(.notebook(notebook)) { if case .notebook = $0 { true } else { false } }
        if let id = cards.first(where: { if case .notebook = $0.kind { true } else { false } })?.id { focus(id) }
    }

    /// Lab notebooks on the canvas, as pages Ask can answer from.
    var notebookPages: [AskedDocument] {
        cards.compactMap { card in
            guard case .notebook(let notebook) = card.kind else { return nil }
            let book = notebook.notebook
            return AskedDocument(
                title: book.title, kind: "lab notebook", summary: book.summary,
                facts: book.trace.cups.map { "Cup \($0.cup.rawValue): \(String(format: "%.1f", $0.start)) °C to \(String(format: "%.1f", $0.end)) °C" },
                catches: [],
                text: book.markdown(date: notebook.date, frames: notebook.frames.count, rehearsal: notebook.isRehearsal)
            )
        }
    }

    /// The paper and the words a note or direction is about.
    private func passage(_ cardID: UUID, _ index: Int) -> (PageDocument, (quote: String, location: SourceLocator.Location))? {
        guard case .notes(let card)? = card(cardID)?.kind, let document = documents[card.paperID] else { return nil }
        let notes = card.linked.notes, directions = card.linked.directions
        if notes.indices.contains(index) {
            guard let quote = notes[index].quote, let location = notes[index].location else { return nil }
            return (document, (quote, location))
        }
        let direction = index - notes.count
        guard directions.indices.contains(direction) else { return nil }
        return (document, (directions[direction].quote, directions[direction].location))
    }

    /// The box around found words on a page, in the photo's normalized coordinates.
    func box(for location: SourceLocator.Location, in document: PageDocument) -> CGRect? {
        guard document.lineBoxes.indices.contains(location.line) else { return nil }
        let lines = document.lineBoxes[location.line...min(location.line + location.extraLines, document.lineBoxes.count - 1)]
        let box = lines.dropFirst().reduce(lines.first) { $0?.union($1) }
        return box.flatMap { $0 == .zero ? nil : $0 }
    }

    /// Shows a new answer beside the page in focus; the one before it folds into the page's group.
    func showAnswer(_ answer: AnswerCard) {
        var answer = answer
        answer.pageID = pageInFocus.flatMap { self.card($0)?.id }
        var added = Card(center: .zero, kind: .answer(answer))
        added.center = freeSpot(for: added.size)
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
            cards.append(added)
            dock(added.id)
            // Earlier answers about the same page stay in its group as chips, the last few of them.
            let earlier = chipOrder.filter { id in
                if case .answer(let old)? = self.card(id)?.kind { old.pageID == answer.pageID } else { false }
            }
            let dropped = Set(earlier.dropLast(Self.answersKept - 1))
            cards.removeAll { dropped.contains($0.id) }
            layoutChips()
        }
    }

    /// Answers kept about one page: the open one and the chips under its page.
    static let answersKept = 4

    /// Puts a card just right of the card in focus (a page, a notebook), sliding that card left
    /// (not past the chips) to make room, and below the phone panel when it would run under it.
    private func dock(_ id: UUID) {
        guard let pageID = pageInFocus, pageID != id, let page = index(of: pageID), !cards[page].isFolded, index(of: id) != nil else {
            // Nothing open to sit beside: it opens on its own.
            open(id, at: nil)
            return
        }
        if let found = index(of: id), cards[found].isFolded {
            cards[found].isFolded = false
            chipOrder.removeAll { $0 == id }
        }
        // One card beside the page at a time; the others fold into chips.
        for other in cards where other.id != id && other.id != pageID && other.kind.sitsBeside && !other.isFolded {
            fold(other.id)
        }
        guard let page = index(of: pageID), let index = index(of: id) else { return }
        let pageSize = cards[page].size, size = cards[index].size
        let leftmost = leftOfChips
        let rightmost = canvasSize.width - 20
        var pageMinX = cards[page].frame.minX
        if pageMinX + pageSize.width + 20 + size.width > rightmost {
            pageMinX = max(leftmost, rightmost - size.width - 20 - pageSize.width)
        }
        cards[page].center.x = pageMinX + pageSize.width / 2
        // On a narrow canvas the answer stays on screen, over the page's right edge.
        let x = min(pageMinX + pageSize.width + 20 + size.width / 2, rightmost - size.width / 2)
        var top = cards[page].frame.minY
        if x + size.width / 2 > canvasSize.width - 320 { top = max(top, panelHeight + 12) }
        // Clear of the voice bar at the bottom middle, unless it's off to the right of it.
        let clearOfVoiceBar = x - size.width / 2 > canvasSize.width / 2 + 260
        top = min(top, canvasSize.height - size.height - (clearOfVoiceBar ? 20 : 90))
        cards[index].center = CGPoint(x: x, y: top + size.height / 2)
        if cards[index].frame.intersects(cards[page].frame) {
            // Too narrow for both: the answer goes on top, where it's read first.
            let card = cards.remove(at: index)
            cards.append(card)
        }
    }

    /// Shows where something came from without a hover, for voice and snapshots.
    func showSource(of target: HoverTarget?) {
        setHovered(target, byHand: false)
    }

    /// The page a card was read from, if any.
    func document(for card: Card) -> PageDocument? {
        switch card.kind {
        case .document(let document): document
        case .loan(let loan): loan.documentID.flatMap { documents[$0] }
        case .scan(let scan): scan.documentID.flatMap { documents[$0] }
        case .comparison(let comparison): comparison.dealer.documentID.flatMap { documents[$0] }
        default: nil
        }
    }

    /// Every page behind the cards on the canvas, chips included, the frontmost card's first.
    var pagesOnCanvas: [PageDocument] {
        var seen = Set<UUID>()
        return cards.reversed().flatMap { card -> [UUID] in
            switch card.kind {
            case .comparison(let comparison): [comparison.dealer.documentID, comparison.other.documentID].compactMap { $0 }
            default: document(for: card).map { [$0.id] } ?? []
            }
        }
        .compactMap { seen.insert($0).inserted ? documents[$0] : nil }
    }

    func provenance(for target: HoverTarget) -> Provenance? {
        switch target {
        case .work(let cardID, let index):
            guard case .related(let related)? = card(cardID)?.kind, let work = related.result.works[safe: index] else { return nil }
            let why = related.result.related.first { $0.work.id == work.id }?.why
            return Provenance(heading: work.title,
                              origin: "OpenAlex · \(work.shortName) · \(work.citations) citation\(work.citations == 1 ? "" : "s") · click to open",
                              quote: work.abstract.isEmpty ? nil : String(work.abstract.prefix(280)) + (work.abstract.count > 280 ? "…" : ""),
                              formula: why ?? work.doi)
        case .cited(let cardID, let index):
            guard let card = card(cardID), let citation = citations(for: card)[safe: index],
                  let document = documents[citation.documentID] else { return nil }
            let crop = citation.cited.location.flatMap { box(for: $0, in: document) }.flatMap { PageCrop.around($0, in: document.image) }
            return Provenance(heading: citation.heading, origin: origin(of: document),
                              quote: citation.cited.quote.isEmpty ? nil : citation.cited.quote,
                              formula: citation.detail, crop: crop?.image, highlight: crop?.highlight)
        case .labStep(let cardID, let index):
            guard case .notebook(let card)? = card(cardID)?.kind, card.notebook.steps.indices.contains(index) else { return nil }
            let step = card.notebook.steps[index]
            let reading = [step.cup.map { cup in step.celsius.map { "Cup \(cup.rawValue): \(String(format: "%.1f", $0)) °C then" } ?? "Cup \(cup.rawValue)" },
                           step.event?.description].compactMap { $0 }.joined(separator: "\n")
            let origin = card.isRehearsal ? "Rehearsal: scripted speech, simulated probes"
                : "Recorded \(card.date.formatted(date: .omitted, time: .shortened)), at \(clockTime(step.seconds)) into the session"
            return Provenance(heading: "\(clockTime(step.seconds)) · \(step.did)", origin: origin, quote: step.said,
                              formula: reading.isEmpty ? nil : reading, crop: card.frame(at: step.seconds))
        case .passage(let cardID, let index):
            guard case .notes(let card)? = card(cardID)?.kind, let (document, passage) = passage(cardID, index) else { return nil }
            let crop = box(for: passage.location, in: document).flatMap { PageCrop.around($0, in: document.image) }
            if card.linked.notes.indices.contains(index) {
                let note = card.linked.notes[index]
                return Provenance(heading: "Your note: “\(note.note)”", origin: origin(of: document), quote: passage.quote,
                                  formula: note.paperSays.map { "The paper says: \($0)" }, crop: crop?.image, highlight: crop?.highlight)
            }
            let direction = card.linked.directions[index - card.linked.notes.count]
            return Provenance(heading: direction.title, origin: origin(of: document), quote: passage.quote,
                              formula: direction.why, crop: crop?.image, highlight: crop?.highlight)
        case .fact(let documentID, let key):
            guard let document = documents[documentID], let fact = document.reading.fact(key) else { return nil }
            let crop = document.factBoxes[key].flatMap { PageCrop.around($0, in: document.image) }
            return Provenance(heading: "\(fact.label): \(fact.asPrinted)", origin: origin(of: document),
                              quote: fact.quote, crop: crop?.image, highlight: crop?.highlight)
        case .catchItem(let documentID, let title):
            guard let document = documents[documentID],
                  let item = document.reading.allCatches.first(where: { $0.title == title }) else { return nil }
            let crop = document.catchBoxes[title].flatMap { PageCrop.around($0, in: document.image) }
            return Provenance(heading: item.title, origin: origin(of: document), quote: item.quote,
                              formula: item.explanation, crop: crop?.image, highlight: crop?.highlight)
        case .derived(let cardID, let name):
            guard let card = card(cardID) else { return nil }
            switch card.kind {
            case .loan(let loanCard):
                return loanProvenance(loanCard.loan, pitchMonths: loanCard.pitch.termMonths,
                                      document: document(for: card), fallback: loanCard.source, name: name)
            case .document(let document):
                switch document.model {
                case .loan(let loan):
                    let written = document.reading.resolvedModel
                    let months = if case .loan(let original) = written { original.termMonths } else { loan.termMonths }
                    return loanProvenance(loan, pitchMonths: months, document: document, fallback: "the page", name: name)
                case .recurring(let cost):
                    return recurringProvenance(cost, document: document)
                case .breakdown(let breakdown):
                    let terms = breakdown.lines.enumerated().map { index, line in
                        let amount = dollars(abs(line.value), cents: true)
                        return index == 0 ? amount : (line.value < 0 ? "− \(amount)" : "+ \(amount)")
                    }
                    let check = breakdown.matchesPage ? "matches the page" : "the page says \(dollars(breakdown.printed, cents: true))"
                    return Provenance(
                        heading: "\(breakdown.label): \(dollars(breakdown.total, cents: true))",
                        origin: "Added up by Grasp from the lines on the page; \(check)",
                        formula: terms.joined(separator: " ") + " = \(dollars(breakdown.total, cents: true))",
                        inputs: breakdown.lines.map { line in
                            Provenance.Input(label: line.label, value: dollars(line.value, cents: true),
                                             source: line.quote.map { "on the page: “\($0)”" } ?? "on the page")
                        }
                    )
                case .none:
                    return nil
                }
            default:
                return nil
            }
        case .answerSource(let cardID, let index):
            guard case .answer(let answer)? = card(cardID)?.kind, answer.sources.indices.contains(index) else { return nil }
            let source = answer.sources[index]
            guard let document = documents[source.documentID] else { return nil }
            let crop = source.box.flatMap { PageCrop.around($0, in: document.image) }
            return Provenance(heading: "Where it says so", origin: origin(of: document), quote: source.quote,
                              crop: crop?.image, highlight: crop?.highlight)
        }
    }

    private func origin(of document: PageDocument) -> String {
        "Read from \(document.reading.title) at \(document.readAt.formatted(date: .omitted, time: .shortened))"
    }

    /// Where a number came from: the words on the page it was read from, or what the card says.
    private func source(of value: Double, in document: PageDocument?, fallback: String) -> String {
        guard let document, let fact = document.reading.source(of: value) else { return fallback }
        return "on \(document.reading.title): “\(fact.quote)”"
    }

    private func loanProvenance(_ loan: LoanTerms, pitchMonths: Int, document: PageDocument?, fallback: String, name: String) -> Provenance {
        let apr = loan.apr.formatted(.percent.precision(.fractionLength(1)))
        let inputs = [
            Provenance.Input(label: "Amount borrowed", value: dollars(loan.principal, cents: true),
                             source: source(of: loan.principal, in: document, fallback: fallback)),
            Provenance.Input(label: "APR", value: apr, source: source(of: loan.apr * 100, in: document, fallback: fallback)),
            Provenance.Input(label: "Months", value: "\(loan.termMonths)",
                             source: loan.termMonths == pitchMonths
                                 ? source(of: Double(loan.termMonths), in: document, fallback: fallback)
                                 : "You twisted it from \(pitchMonths)"),
        ]
        let (heading, formula): (String, String) = switch name {
        case "monthly":
            ("Monthly payment: \(dollars(loan.monthlyPayment, cents: true))", "P × r ÷ (1 − (1 + r)^−n), r = APR ÷ 12")
        case "interest":
            ("Interest: \(dollars(loan.totalInterest))", "\(dollars(loan.totalPaid)) paid − \(dollars(loan.principal)) borrowed")
        default:
            ("Total paid: \(dollars(loan.totalPaid))", "\(dollars(loan.monthlyPayment, cents: true)) a month × \(loan.termMonths) months")
        }
        return Provenance(heading: heading, origin: "Worked out by Grasp, not by the AI", formula: formula, inputs: inputs)
    }

    private func recurringProvenance(_ cost: RecurringCost, document: PageDocument) -> Provenance {
        var parts: [String] = []
        var inputs: [Provenance.Input] = []
        func add(_ label: String, _ value: Double, cents: Bool = true) {
            inputs.append(Provenance.Input(label: label, value: dollars(value, cents: cents),
                                           source: source(of: value, in: document, fallback: "the page")))
        }
        if let promo = cost.promoMonthly, cost.promoMonthsCounted > 0 {
            parts.append("\(cost.promoMonthsCounted) × \(dollars(promo))")
            add("Promo price", promo)
        }
        let regular = cost.months - cost.promoMonthsCounted
        if regular > 0 { parts.append("\(regular) × \(dollars(cost.monthly))") }
        add("Regular price", cost.monthly)
        if cost.extraMonthly != 0 {
            parts.append("\(cost.months) × \(dollars(cost.extraMonthly)) extras")
            for extra in document.reading.model.extraMonthly ?? [] where document.reading.source(of: extra) != nil {
                add(extra < 0 ? "Monthly discount" : "Other monthly charge", extra)
            }
        }
        if cost.upfront > 0 {
            parts.append("\(dollars(cost.upfront)) up front")
            add("One-time charges", cost.upfront)
        }
        let written = document.reading.resolvedModel
        if case .recurring(let original) = written, original.months != cost.months {
            inputs.append(Provenance.Input(label: "Months", value: "\(cost.months)", source: "You twisted it from \(original.months)"))
        }
        return Provenance(
            heading: "Total over \(cost.months) months: \(dollars(cost.total))",
            origin: "Worked out by Grasp, not by the AI",
            formula: parts.joined(separator: " + "),
            inputs: inputs
        )
    }
}
