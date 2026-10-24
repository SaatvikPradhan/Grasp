import Charts
import GraspKit
import SwiftUI

/// The car loan's true cost: amount financed plus interest, compared with the pitched term.
struct ChartCardView: View {
    let card: ChartCard
    let isHeld: Bool

    private var loan: LoanTerms { card.loan }
    private var pitch: LoanTerms { loan.with(termMonths: card.pitchTermMonths) }
    /// Fixed so the bar visibly shrinks and grows as the term changes.
    private var maxTotal: Double { loan.with(termMonths: CanvasModel.termRange.upperBound).totalPaid }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CAR LOAN · TRUE COST")
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
                Text("\(dollars(loan.monthlyPayment)) a month × \(loan.termMonths) months at \(loan.apr.formatted(.percent.precision(.fractionLength(1))))")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .contentTransition(.numericText())
            }

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
            .frame(height: 58)

            HStack(alignment: .firstTextBaseline) {
                termTicks
                Spacer()
                comparison
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isHeld ? Theme.hot : Theme.line, lineWidth: isHeld ? 2 : 1)
        )
        .shadow(color: .black.opacity(isHeld ? 0.5 : 0.3), radius: isHeld ? 24 : 12, y: isHeld ? 14 : 6)
        .scaleEffect(isHeld ? 1.03 : 1)
        .animation(.spring(duration: 0.35), value: loan.termMonths)
        .animation(.spring(duration: 0.25), value: isHeld)
    }

    private var termTicks: some View {
        HStack(spacing: 6) {
            ForEach(Array(stride(from: CanvasModel.termRange.lowerBound, through: CanvasModel.termRange.upperBound, by: CanvasModel.termStep)), id: \.self) { term in
                Text("\(term)")
                    .font(.system(size: 12, weight: term == loan.termMonths ? .bold : .regular, design: .monospaced))
                    .foregroundStyle(term == loan.termMonths ? Theme.paper : Theme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(term == loan.termMonths ? Theme.hot : .clear))
            }
        }
    }

    @ViewBuilder
    private var comparison: some View {
        let saved = pitch.totalPaid - loan.totalPaid
        if abs(saved) < 1 {
            Text("the \(card.pitchTermMonths)-month pitch")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
        } else {
            Text(saved > 0 ? "saves \(dollars(saved))" : "costs \(dollars(-saved)) more")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(saved > 0 ? Theme.accent : Theme.warn)
                .contentTransition(.numericText(value: saved))
        }
    }

    private func dollars(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}

#Preview {
    ChartCardView(card: ChartCard(center: .zero, loan: LoanTerms.demoContract.with(termMonths: 48), pitchTermMonths: 72), isHeld: false)
        .frame(width: 460, height: 300)
        .padding(40)
        .background(Theme.paper)
}
