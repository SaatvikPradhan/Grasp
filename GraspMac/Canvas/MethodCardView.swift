import GraspKit
import SwiftUI

/// A paper's method as a map: the question; what was varied, what was measured and how it was
/// analysed, left to right; how many trials; and what was held the same against what wasn't
/// controlled. Hover any box for its sentence in the paper.
struct MethodCardView: View {
    let cardID: UUID
    let card: MethodCard

    private var map: MethodMap { card.map }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("METHOD MAP")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text(card.paperTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("QUESTION")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                Text(map.question?.name ?? "Not stated on this page")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.12)))
            .modifier(Cites(card: cardID, index: index(map.question)))

            HStack(alignment: .top, spacing: 6) {
                column("WHAT WAS VARIED", map.varied)
                arrow
                column("WHAT WAS MEASURED", map.measured)
                arrow
                column("HOW IT WAS ANALYSED", [map.analysis].compactMap { $0 })
            }

            if let trials = map.trials {
                Text(trials.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.paper)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.accent))
                    .modifier(Cites(card: cardID, index: index(trials)))
                    .frame(height: 28)
            }

            HStack(alignment: .top, spacing: 16) {
                list("HELD THE SAME", map.controlled, symbol: "checkmark.circle.fill", color: Theme.accent)
                list("NOT CONTROLLED", map.notControlled, symbol: "exclamationmark.triangle.fill", color: Theme.hot)
            }

            Spacer(minLength: 0)
            Text("Hover any box for its sentence in the paper · what wasn't controlled is where research can go next")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .frame(width: 18)
            .padding(.top, 40)
    }

    private func column(_ title: String, _ items: [MethodMap.Item]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if let detail = item.detail {
                        Text(detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                .frame(height: 38, alignment: .topLeading)
                .modifier(Cites(card: cardID, index: index(item)))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
    }

    private func list(_ title: String, _ items: [MethodMap.Item], symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .frame(height: 18, alignment: .leading)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name + (item.cited == nil ? " (not in the paper)" : ""))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        if let detail = item.detail {
                            Text(detail)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(height: 36, alignment: .topLeading)
                .modifier(Cites(card: cardID, index: index(item)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func index(_ item: MethodMap.Item?) -> Int? {
        item.flatMap { map.items.firstIndex(of: $0) }
    }
}

/// Hover for a box that has words in the paper behind it.
private struct Cites: ViewModifier {
    let card: UUID
    let index: Int?

    func body(content: Content) -> some View {
        if let index {
            content.hoverSource(.cited(card: card, index: index))
        } else {
            content
        }
    }
}
