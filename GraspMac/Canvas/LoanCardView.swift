import Charts
import GraspKit
import SwiftUI

extension LoanTerms: LoanTermsLike {}

/// One loan's true cost: amount financed plus interest, against the salesperson's pitch.
/// Bars show the split; lines show the total paid month by month.
struct LoanCardView: View {
    let cardID: UUID
    let card: LoanCard
    let style: Card.Style

    private var loan: LoanTerms { card.loan }
    /// Fixed so the chart visibly grows and shrinks as the term changes.
    private var maxTotal: Double {
        max(loan.with(termMonths: LoanCard.termRange.upperBound).totalPaid,
            card.pitch.with(termMonths: LoanCard.termRange.upperBound).totalPaid)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(card.title.uppercased()) · TRUE COST")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Label("twist to change term", systemImage: "dial.medium")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(dollars(loan.totalPaid))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: loan.totalPaid))
                    .hoverSource(.derived(card: cardID, name: "total"))
                Text("\(dollars(loan.monthlyPayment)) a month × \(loan.termMonths) months at \(loan.apr.formatted(.percent.precision(.fractionLength(1))))")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .contentTransition(.numericText())
                    .hoverSource(.derived(card: cardID, name: "monthly"))
            }

            Group {
                switch style {
                case .primary: bars
                case .alternate: lines
                }
            }
            .frame(height: 72)
            // Charts draw marks past their axes; keep everything inside the card.
            .clipped()

            Text(card.source)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)

            HStack(alignment: .firstTextBaseline) {
                TermTicks(current: loan.termMonths)
                Spacer()
                comparison
            }
        }
        .animation(.spring(duration: 0.35), value: loan.termMonths)
    }

    private var bars: some View {
        Chart {
            BarMark(x: .value("Dollars", loan.principal), y: .value("Loan", "Total"))
                .foregroundStyle(by: .value("Part", "Amount financed"))
            BarMark(x: .value("Dollars", loan.totalInterest), y: .value("Loan", "Total"))
                .foregroundStyle(by: .value("Part", "Interest"))
                .annotation(position: .overlay, alignment: .trailing) {
                    Text(dollars(loan.totalInterest))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.paper)
                }
        }
        .chartForegroundStyleScale(["Amount financed": Theme.accent.opacity(0.55), "Interest": Theme.warn])
        .chartXScale(domain: 0...maxTotal)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(position: .bottom, alignment: .leading, spacing: 6)
    }

    private var lines: some View {
        Chart {
            ForEach(PaidPoint.series(for: card.pitch)) { point in
                LineMark(x: .value("Month", point.month), y: .value("Paid", point.paid), series: .value("Loan", "Pitch"))
                    .foregroundStyle(Theme.muted)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            ForEach(PaidPoint.series(for: loan)) { point in
                LineMark(x: .value("Month", point.month), y: .value("Paid", point.paid), series: .value("Loan", "This"))
                    .foregroundStyle(Theme.hot)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
        }
        .chartXScale(domain: 0...LoanCard.termRange.upperBound)
        .chartYScale(domain: 0...maxTotal)
        .chartXAxis {
            AxisMarks(values: [0, 24, 48, 72]) { value in
                AxisValueLabel { if let month = value.as(Int.self) { Text("\(month) mo") } }
            }
        }
        .chartYAxis(.hidden)
    }

    @ViewBuilder
    private var comparison: some View {
        let saved = card.savedVersusPitch
        if abs(saved) < 1 {
            Text("the \(card.pitch.termMonths)-month pitch")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
        } else {
            Text(saved > 0 ? "saves \(dollars(saved))" : "costs \(dollars(-saved)) more")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(saved > 0 ? Theme.accent : Theme.warn)
                .contentTransition(.numericText(value: saved))
        }
    }
}
