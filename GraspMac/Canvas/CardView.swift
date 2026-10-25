import GraspKit
import SwiftUI

/// The frame every card shares: surface, border, lift while held, glow while merging.
struct CardView: View {
    let card: Card
    let isHeld: Bool
    let isMergeCandidate: Bool
    /// Over the trash: letting go deletes it.
    var isTrashTarget = false
    /// What questions and commands go to, when there's more than one card.
    var isFocused = false
    let probes: ProbeHub
    let guide: ProtocolGuide

    var body: some View {
        content
            .padding(padding)
            .frame(width: card.size.width, height: card.size.height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(borderColor, lineWidth: borderWidth))
            .overlay(alignment: .top) {
                if isMergeCandidate {
                    Text("Push together to compare")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.paper)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.accent))
                        .offset(y: -12)
                        .transition(.opacity)
                }
            }
            .shadow(color: .black.opacity(isHeld ? 0.5 : 0.3), radius: isHeld ? 24 : 12, y: isHeld ? 14 : 6)
            .scaleEffect(isTrashTarget ? 0.7 : isHeld ? 1.03 : 1)
            .opacity(isTrashTarget ? 0.6 : 1)
            .animation(.spring(duration: 0.25), value: isTrashTarget)
            .animation(.spring(duration: 0.25), value: isHeld)
            .animation(.spring(duration: 0.25), value: isMergeCandidate)
            .animation(.spring(duration: 0.4), value: card.size)
    }

    @ViewBuilder
    private var content: some View {
        if card.isFolded {
            FoldedCardView(card: card)
        } else {
            unfolded
        }
    }

    @ViewBuilder
    private var unfolded: some View {
        switch card.kind {
        case .loan(let loan):
            LoanCardView(cardID: card.id, card: loan, style: card.style)
        case .comparison(let comparison):
            ComparisonCardView(comparison: comparison, style: card.style)
        case .temperatures:
            TemperatureCardView(hub: probes, style: card.style)
        case .scan(let scan):
            ScanCardView(scan: scan)
        case .advice(let advice):
            AdviceCardView(advice: advice)
        case .pitch(let checks):
            PitchCardView(checks: checks)
        case .document(let document):
            if let video = document.video {
                VideoCardView(cardID: card.id, document: document, video: video)
            } else {
                DocumentCardView(cardID: card.id, document: document)
            }
        case .answer(let answer):
            AnswerCardView(cardID: card.id, card: answer)
        case .notes(let notes):
            NotesCardView(cardID: card.id, card: notes)
        case .notebook(let notebook):
            NotebookCardView(cardID: card.id, card: notebook)
        case .model(let model):
            ModelCardView(cardID: card.id, card: model, probes: probes)
        case .guide(let card):
            GuideCardView(cardID: self.card.id, card: card, guide: guide, probes: probes)
        case .method(let method):
            MethodCardView(cardID: card.id, card: method)
        case .related(let related):
            RelatedCardView(cardID: card.id, card: related)
        case .letter(let letter):
            LetterCardView(cardID: card.id, card: letter)
        case .deepDive(let dive):
            DeepDiveCardView(cardID: card.id, card: dive)
        case .notePad(let pad):
            NotePadCardView(cardID: card.id, card: pad)
        }
    }

    private var padding: CGFloat {
        if card.isFolded { return 10 }
        if case .scan = card.kind { return 16 }
        return 20
    }

    private var borderColor: Color {
        if isTrashTarget { return Theme.warn }
        if isMergeCandidate { return Theme.accent }
        if isHeld { return Theme.hot }
        return isFocused ? Theme.accent : Theme.line
    }

    private var borderWidth: CGFloat {
        if isTrashTarget || isMergeCandidate { return 3 }
        return isHeld || isFocused ? 2 : 1
    }
}

/// A card out of focus, as a chip: a page's title and what's wrong with it, or what a card
/// beside a page holds, smaller, under its page. Grab or click it to open it.
struct FoldedCardView: View {
    let card: Card

    @Environment(CanvasModel.self) private var canvas

    private var isSide: Bool { !card.kind.isPage }

    var body: some View {
        HStack(spacing: isSide ? 8 : 10) {
            if let photo {
                Image(nsImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: isSide ? 14 : 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: isSide ? 22 : 34, height: isSide ? 28 : 44)
            }
            VStack(alignment: .leading, spacing: isSide ? 1 : 3) {
                Text(title)
                    .font(.system(size: isSide ? 12 : 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                detail
                    .font(.system(size: isSide ? 11 : 12, weight: .medium))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            // What's tucked under it when there are too many groups to show in full.
            let tucked = canvas.tuckedCount(under: card.id)
            if tucked > 0 {
                Text("+\(tucked)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.paper)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.muted))
            }
        }
    }

    private var photo: NSImage? {
        switch card.kind {
        case .document(let document): document.image
        case .scan(let scan): scan.image
        default: nil
        }
    }

    private var symbol: String {
        switch card.kind {
        case .answer: "text.bubble"
        case .notes: "checklist"
        case .model: "function"
        case .notebook: "book.closed"
        case .guide: "list.number"
        case .method: "point.3.connected.trianglepath.dotted"
        case .related: "books.vertical"
        case .letter: "envelope"
        case .deepDive: "globe"
        case .notePad: "square.and.pencil"
        case .loan: "car"
        case .comparison: "arrow.left.arrow.right"
        case .advice: "quote.bubble"
        case .pitch: "ear"
        default: "rectangle"
        }
    }

    private var title: String {
        switch card.kind {
        case .document(let document): document.reading.title
        case .answer(let answer): "“\(answer.question)”"
        case .notes(let notes): "Your notes on \(notes.paperTitle)"
        case .model(let model): "Live model: \(model.paperTitle)"
        case .notebook(let notebook): notebook.notebook.title
        case .guide(let guide): guide.lab.title
        case .method(let method): "Method: \(method.paperTitle)"
        case .related(let related): "Related work: \(related.paperTitle)"
        case .letter(let letter): "Dispute to \(letter.letter.company)"
        case .loan(let loan): loan.title
        case .comparison: "Dealer vs credit union"
        case .scan(let scan):
            if case .read(let reading) = scan.status { ScanCardView.title(reading.documentType) } else { "Photo" }
        case .advice: "What to say"
        case .pitch: "The pitch, checked"
        case .temperatures: "Cup temperatures"
        case .deepDive(let dive): dive.isPlan ? "What to do" : "Deep dive: \(dive.subject.topic)"
        case .notePad(let pad): pad.title
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch card.kind {
        case .document(let document):
            let mistakes = document.reading.mismatches.count
            let catches = document.reading.allCatches.count - mistakes
            HStack(spacing: 8) {
                if mistakes > 0 {
                    Text(mistakes == 1 ? "1 doesn't add up" : "\(mistakes) don't add up").foregroundStyle(Theme.warn)
                }
                if catches > 0 {
                    Text("\(catches) catch\(catches == 1 ? "" : "es")").foregroundStyle(Theme.hot)
                }
                if mistakes == 0 && catches == 0 {
                    Text(document.reading.kind).foregroundStyle(Theme.muted)
                }
            }
        case .answer(let answer):
            Text(answer.answer.answer).foregroundStyle(Theme.muted)
        case .notes(let notes):
            let differing = notes.linked.notes.filter { $0.status == .differs }.count
            Text("\(notes.linked.notes.count) notes · \(differing) differ").foregroundStyle(differing > 0 ? Theme.hot : Theme.muted)
        case .model(let model):
            let wrong = model.model.mismatches.count
            Text(wrong == 0 ? "\(model.model.conditions.count) conditions" : "\(wrong) result\(wrong == 1 ? "" : "s") don't follow")
                .foregroundStyle(wrong > 0 ? Theme.warn : Theme.muted)
        case .notebook(let notebook):
            Text("\(notebook.notebook.steps.count) steps · \(clockTime(notebook.notebook.duration))").foregroundStyle(Theme.muted)
        case .guide(let guide):
            Text("protocol · \(guide.lab.steps.count) steps").foregroundStyle(Theme.muted)
        case .method(let method):
            Text("\(method.map.varied.count) varied · \(method.map.notControlled.count) not controlled").foregroundStyle(Theme.muted)
        case .letter(let letter):
            Text("\(dollars(letter.letter.total, cents: true)) to get back").foregroundStyle(Theme.hot)
        case .related(let related):
            let open = related.result.directions.filter { $0.verdict == .open }.count
            Text("\(related.result.related.count) papers · \(open) direction\(open == 1 ? "" : "s") open").foregroundStyle(Theme.muted)
        case .loan(let loan):
            Text("\(dollars(loan.loan.totalPaid)) over \(loan.loan.termMonths) months").foregroundStyle(Theme.muted)
        case .comparison(let comparison):
            Text("compared at \(comparison.termMonths) months").foregroundStyle(Theme.muted)
        case .scan(let scan):
            if case .read(let reading) = scan.status, !reading.addOns.isEmpty {
                Text("add-ons · \(dollars(reading.addOnTotal))").foregroundStyle(Theme.warn)
            } else {
                Text("read").foregroundStyle(Theme.muted)
            }
        case .advice(let advice):
            Text("\(advice.lines.count) things to ask").foregroundStyle(Theme.muted)
        case .pitch(let checks):
            Text("\(checks.count) number\(checks.count == 1 ? "" : "s") checked").foregroundStyle(Theme.muted)
        case .deepDive(let card):
            if let dive = card.dive, card.isPlan {
                Text("\(dive.steps.count) steps · \(dive.findings.count) comparisons").foregroundStyle(Theme.hot)
            } else if let dive = card.dive {
                Text("\(dive.findings.count) findings · \(dive.sources.count) sources").foregroundStyle(Theme.muted)
            } else {
                Text(card.failure == nil ? "searching the web…" : "couldn't search").foregroundStyle(Theme.muted)
            }
        case .notePad(let pad):
            Text(pad.lines.first ?? "empty").foregroundStyle(Theme.muted)
        case .temperatures:
            EmptyView()
        }
    }
}

/// The tray behind a group of chips: a page and what sat beside it, or the car deal.
struct ChipTrayView: View {
    let tray: ChipTray

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Theme.surface.opacity(0.45))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(tray.isInFocus ? Theme.accent.opacity(0.7) : Theme.line, lineWidth: tray.isInFocus ? 1.5 : 1)
            )
            .overlay(alignment: .topLeading) {
                if let caption = tray.caption {
                    Text(caption.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Theme.muted)
                        .padding(.leading, 12)
                        .padding(.top, 9)
                }
            }
            .frame(width: tray.frame.width, height: tray.frame.height)
    }
}

/// The bin in the corner, shown while a card is held. Red when letting go would delete.
struct TrashBin: View {
    let isHot: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isHot ? Theme.warn : Theme.surface)
                .overlay(Circle().stroke(isHot ? Theme.warn : Theme.line, lineWidth: 2))
            Image(systemName: isHot ? "trash.fill" : "trash")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(isHot ? Theme.paper : Theme.muted)
        }
        .frame(width: 84, height: 84)
        .scaleEffect(isHot ? 1.2 : 1)
        .animation(.spring(duration: 0.25), value: isHot)
    }
}

/// Dollars without cents, the way the cards show totals.
func dollars(_ value: Double, cents: Bool = false) -> String {
    value.formatted(.currency(code: "USD").precision(.fractionLength(cents ? 2 : 0)))
}

/// Month by month, how much has been paid on a loan so far: the line style of the loan charts.
struct PaidPoint: Identifiable {
    var month: Int
    var paid: Double
    var id: Int { month }

    static func series(for loan: LoanTermsLike) -> [PaidPoint] {
        let months = Array(stride(from: 0, to: loan.termMonths, by: 3)) + [loan.termMonths]
        return months.map { PaidPoint(month: $0, paid: loan.monthlyPayment * Double($0)) }
    }
}

/// What `PaidPoint.series` needs, so it doesn't depend on a particular loan type.
protocol LoanTermsLike {
    var termMonths: Int { get }
    var monthlyPayment: Double { get }
}

/// The term scale under a loan chart, with the current term lit.
struct TermTicks: View {
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(stride(from: LoanCard.termRange.lowerBound, through: LoanCard.termRange.upperBound, by: LoanCard.termStep)), id: \.self) { term in
                Text("\(term)")
                    .font(.system(size: 12, weight: term == current ? .bold : .regular, design: .monospaced))
                    .foregroundStyle(term == current ? Theme.paper : Theme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(term == current ? Theme.hot : .clear))
            }
        }
    }
}
