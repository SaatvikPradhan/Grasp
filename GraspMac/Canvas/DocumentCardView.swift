import GraspKit
import SwiftUI

/// Any page as one card: what it is, the model you can twist, every number (hover for its
/// source), and the catches in the fine print.
struct DocumentCardView: View {
    let cardID: UUID
    let document: PageDocument

    private var reading: PageReading { document.reading }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(reading.kind.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    Text(reading.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(reading.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(nsImage: document.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            modelSection

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 4) {
                ForEach(document.shownFacts) { fact in
                    HStack(spacing: 6) {
                        Text(fact.label)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(fact.asPrinted)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12))
                    .frame(height: 20)
                    .hoverSource(.fact(document: document.id, key: fact.key))
                }
            }

            if !document.shownCatches.isEmpty {
                Text("CATCHES")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.warn)
                ForEach(document.shownCatches) { catchItem in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(catchItem.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(catchItem.severity == .low ? Theme.hot : Theme.warn)
                            .lineLimit(1)
                        Text(catchItem.explanation)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(2)
                    }
                    .frame(height: 40, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hoverSource(.catchItem(document: document.id, title: catchItem.title))
                }
            }

            Spacer(minLength: 0)
            Text("Hover any number to see where it came from")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
        }
        .animation(.spring(duration: 0.35), value: document.months)
    }

    @ViewBuilder
    private var modelSection: some View {
        switch document.model {
        case .loan(let loan):
            modelBlock(
                label: "TOTAL YOU'D PAY",
                total: loan.totalPaid,
                detail: "\(dollars(loan.monthlyPayment, cents: true)) a month × \(loan.termMonths) months at \(loan.apr.formatted(.percent.precision(.fractionLength(1))))",
                months: loan.termMonths
            )
        case .recurring(let cost):
            modelBlock(
                label: "TOTAL OVER \(cost.months) MONTHS",
                total: cost.total,
                detail: recurringDetail(cost),
                months: cost.months
            )
        case .breakdown(let items):
            let total = items.compactMap(\.value).reduce(0, +)
            Text("\(items.count) charges adding up to \(dollars(total, cents: true))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .hoverSource(.derived(card: cardID, name: "total"))
        case .none:
            EmptyView()
        }
    }

    private func modelBlock(label: String, total: Double, detail: String, months: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Label("twist to change months", systemImage: "dial.medium")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            Text(dollars(total))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText(value: total))
                .hoverSource(.derived(card: cardID, name: "total"))
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .frame(height: 108, alignment: .top)
    }

    private func recurringDetail(_ cost: RecurringCost) -> String {
        var parts: [String] = []
        if let promo = cost.promoMonthly, cost.promoMonthsCounted > 0 {
            parts.append("\(dollars(promo)) for \(cost.promoMonthsCounted) mo, then \(dollars(cost.monthly))")
        } else {
            parts.append("\(dollars(cost.monthly)) a month")
        }
        if cost.extraMonthly != 0 {
            parts.append("\(cost.extraMonthly > 0 ? "+" : "−")\(dollars(abs(cost.extraMonthly))) a month extras")
        }
        if cost.upfront > 0 {
            parts.append("\(dollars(cost.upfront)) up front")
        }
        return parts.joined(separator: " · ")
    }
}
