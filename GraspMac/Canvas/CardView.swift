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
        if card.isFolded, case .document(let document) = card.kind {
            FoldedPageView(document: document)
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
            DocumentCardView(cardID: card.id, document: document)
        case .answer(let answer):
            AnswerCardView(cardID: card.id, card: answer)
        case .notes(let notes):
            NotesCardView(cardID: card.id, card: notes)
        case .notebook(let notebook):
            NotebookCardView(cardID: card.id, card: notebook)
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

/// A page out of focus: what it is and what's wrong with it. Grab or click it to open it.
struct FoldedPageView: View {
    let document: PageDocument

    var body: some View {
        let mistakes = document.reading.mismatches.count
        let catches = document.reading.allCatches.count - mistakes
        HStack(spacing: 10) {
            Image(nsImage: document.image)
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(document.reading.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if mistakes > 0 {
                        Text(mistakes == 1 ? "1 doesn't add up" : "\(mistakes) don't add up")
                            .foregroundStyle(Theme.warn)
                    }
                    if catches > 0 {
                        Text("\(catches) catch\(catches == 1 ? "" : "es")")
                            .foregroundStyle(Theme.hot)
                    }
                    if mistakes == 0 && catches == 0 {
                        Text(document.reading.kind)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
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
