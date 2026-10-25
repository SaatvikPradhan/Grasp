import Charts
import GraspKit
import SwiftUI

/// Dealer financing against another lender at the same term, after pushing their cards together.
struct ComparisonCardView: View {
    let comparison: Comparison
    let style: Card.Style

    private var dealer: LoanTerms { comparison.dealer.loan }
    private var other: LoanTerms { comparison.other.loan }
    private var maxTotal: Double {
        max(dealer.with(termMonths: LoanCard.termRange.upperBound).totalPaid,
            comparison.dealer.pitch.with(termMonths: LoanCard.termRange.upperBound).totalPaid)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DEALER vs CREDIT UNION · \(comparison.termMonths) MONTHS")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Label("twist to change term", systemImage: "dial.medium")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }

            HStack(alignment: .top, spacing: 24) {
                summary(comparison.dealer, color: Theme.warn)
                summary(comparison.other, color: Theme.accent)
            }

            Group {
                switch style {
                case .primary: bars
                case .alternate: lines
                }
            }
            .frame(height: 84)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                let versusDealer = dealer.totalPaid.rounded() - other.totalPaid.rounded()
                Text(versusDealer >= 0
                     ? "Credit union saves \(dollars(versusDealer)) at \(comparison.termMonths) months"
                     : "Dealer is \(dollars(-versusDealer)) cheaper at \(comparison.termMonths) months")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(versusDealer >= 0 ? Theme.accent : Theme.warn)
                    .contentTransition(.numericText(value: versusDealer))
                Text("\(dollars(comparison.other.savedVersusPitch)) less than the \(comparison.dealer.pitch.termMonths)-month pitch")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .contentTransition(.numericText())
            }

            TermTicks(current: comparison.termMonths)
        }
        .animation(.spring(duration: 0.35), value: comparison.termMonths)
    }

    private func summary(_ card: LoanCard, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(card.role == .dealer ? "Dealer" : "Credit union") · \(card.loan.apr.formatted(.percent.precision(.fractionLength(1))))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(dollars(card.loan.totalPaid))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText(value: card.loan.totalPaid))
            Text("\(dollars(card.loan.monthlyPayment)) a month")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        }
    }

    private var bars: some View {
        Chart {
            ForEach([(name: "Dealer", card: comparison.dealer), (name: "Credit union", card: comparison.other)], id: \.name) { row in
                let name = row.name, card = row.card
                BarMark(x: .value("Dollars", card.loan.principal), y: .value("Lender", name))
                    .foregroundStyle(by: .value("Part", "Amount financed"))
                BarMark(x: .value("Dollars", card.loan.totalInterest), y: .value("Lender", name))
                    .foregroundStyle(by: .value("Part", "Interest"))
                    .annotation(position: .overlay, alignment: .trailing) {
                        Text(dollars(card.loan.totalInterest))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.paper)
                    }
            }
        }
        .chartForegroundStyleScale(["Amount financed": Theme.accent.opacity(0.55), "Interest": Theme.warn])
        .chartXScale(domain: 0...maxTotal)
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
    }

    private var lines: some View {
        Chart {
            ForEach(PaidPoint.series(for: dealer)) { point in
                LineMark(x: .value("Month", point.month), y: .value("Paid", point.paid), series: .value("Lender", "Dealer"))
                    .foregroundStyle(Theme.warn)
            }
            ForEach(PaidPoint.series(for: other)) { point in
                LineMark(x: .value("Month", point.month), y: .value("Paid", point.paid), series: .value("Lender", "Credit union"))
                    .foregroundStyle(Theme.accent)
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
}
