import AppKit
import Charts
import GraspKit
import SwiftUI

/// Papers close to this one, from OpenAlex, placed by year and citations; the closest few with
/// why they relate (hover for the abstract, click to open); and for each direction the research
/// could take, whether a listed paper already did it.
struct RelatedCardView: View {
    let cardID: UUID
    let card: RelatedCard

    private var result: RelatedWork { card.result }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("RELATED WORK · FROM OPENALEX")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text(card.paperTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }

            map
                .frame(height: 96)

            Text("CLOSEST PAPERS")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)
            ForEach(Array(result.related.prefix(4).enumerated()), id: \.offset) { _, found in
                VStack(alignment: .leading, spacing: 1) {
                    Text(found.work.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text("\(found.work.shortName) · \(found.work.citations) citation\(found.work.citations == 1 ? "" : "s") · \(found.why)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                .frame(height: 34, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .modifier(WorkHover(card: cardID, index: result.works.firstIndex(of: found.work)))
                .onTapGesture { found.work.link.map { NSWorkspace.shared.open($0) } }
            }

            Text("HAS ANYONE DONE THIS?")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.hot)
                .padding(.top, 4)
            ForEach(Array(result.directions.enumerated()), id: \.offset) { index, direction in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(direction.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(verdict(direction))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(direction.verdict == .open ? Theme.paper : Theme.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(direction.verdict == .open ? Theme.accent : Theme.line))
                            .fixedSize()
                    }
                    Text(direction.note)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                .frame(height: 40, alignment: .topLeading)
                .hoverSource(.cited(card: cardID, index: index))
            }
            Spacer(minLength: 0)
            Text("Every paper is a real OpenAlex record · hover for its abstract, click to open it")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
    }

    /// The papers by year and citations: related ones green, ones a direction rests on orange.
    private var map: some View {
        let related = Set(result.related.map(\.work.id))
        let dated = result.works.filter { $0.year != nil }
        let years = dated.compactMap(\.year)
        // Names only on the few most-cited, so they don't pile up on the uncited ones.
        let named = Set(dated.filter { $0.citations >= 3 }.sorted { $0.citations > $1.citations }.prefix(3).map(\.id))
        return Chart {
            ForEach(dated) { work in
                PointMark(x: .value("Year", work.year ?? 0), y: .value("Citations", max(work.citations, 1)))
                    .foregroundStyle(related.contains(work.id) ? Theme.accent : Theme.hot)
                    .symbolSize(related.contains(work.id) ? 70 : 50)
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        if named.contains(work.id) {
                            Text(work.shortName)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.muted)
                        }
                    }
            }
        }
        .chartXScale(domain: (years.min() ?? 2000) - 2...(years.max() ?? 2026) + 2)
        .chartYScale(type: .log)
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel { if let year = value.as(Int.self) { Text(String(year)) } }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [1, 10, 100, 1000]) { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel { if let count = value.as(Int.self) { Text("\(count)") } }
            }
        }
    }

    private func verdict(_ direction: RelatedWork.Direction) -> String {
        let names = direction.evidence.map(\.shortName).joined(separator: ", ")
        switch direction.verdict {
        case .studied: return "Studied: \(names)"
        case .partly: return "Partly: \(names)"
        case .open: return "Looks open"
        }
    }
}

/// Hover for a paper, when it's on the card's list.
private struct WorkHover: ViewModifier {
    let card: UUID
    let index: Int?

    func body(content: Content) -> some View {
        if let index {
            content.hoverSource(.work(card: card, index: index))
        } else {
            content
        }
    }
}
