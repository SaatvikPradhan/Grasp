import AppKit
import GraspKit
import SwiftUI

/// What the web says about one thing on a page: findings, each with the numbered sources that
/// back it (hover for them, click to open the first), the bottom line, and the sources themselves.
struct DeepDiveCardView: View {
    let cardID: UUID
    let card: DeepDiveCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.isPlan ? "WHAT TO DO · CHECKED AGAINST THE MARKET" : "DEEP DIVE · FROM THE WEB")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text(card.subject.topic)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let quote = card.subject.quote, !quote.isEmpty {
                    Text("\u{201C}\(quote)\u{201D}" + (card.subject.source.map { " · \($0)" } ?? ""))
                        .font(.system(size: 12).italic())
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }

            if let dive = card.dive {
                findings(dive)
            } else if let failure = card.failure {
                Text(failure)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.warn)
                    .lineLimit(3)
            } else {
                searching
            }
            Spacer(minLength: 0)
            Text(footer)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
    }

    private var searching: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.pulse)
            Text("Searching the web…")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
        .padding(.top, 18)
    }

    @ViewBuilder
    private func findings(_ dive: DeepDive) -> some View {
        if card.isPlan, !dive.findings.isEmpty {
            Text("HOW IT COMPARES")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)
        }
        ForEach(Array(dive.findings.enumerated()), id: \.offset) { index, finding in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(Theme.accent).frame(width: 5, height: 5).offset(y: -3)
                (Text(finding.text).foregroundStyle(Theme.ink)
                    + Text(finding.sources.map { " [\($0 + 1)]" }.joined()).foregroundStyle(Theme.accent).bold())
                    .font(.system(size: 13))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .hoverSource(.webFinding(card: cardID, index: index))
            .onTapGesture { finding.sources.first.flatMap { dive.sources[safe: $0] }.map { NSWorkspace.shared.open($0.url) } }
        }

        if !dive.steps.isEmpty {
            Text("WHAT TO DO")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.hot)
                .padding(.top, 4)
            ForEach(Array(dive.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.hot)
                        .frame(width: 14, alignment: .trailing)
                    (Text(step.text).foregroundStyle(Theme.ink)
                        + Text(step.numbersChecked ? "" : "  (amount not on the page)").foregroundStyle(Theme.muted).italic())
                        .font(.system(size: 13))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .hoverSource(.planStep(card: cardID, index: index))
            }
        }

        if let bottomLine = dive.bottomLine {
            VStack(alignment: .leading, spacing: 3) {
                Text("BOTTOM LINE")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.hot)
                Text(bottomLine)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let math = dive.bottomLineMath {
                    Text("Worked out by Grasp: \(math)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                }
            }
            .padding(.top, 4)
        }

        if !dive.sources.isEmpty {
            Text("SOURCES")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .padding(.top, 4)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: 5) {
                ForEach(Array(dive.sources.prefix(card.isPlan ? 4 : 6).enumerated()), id: \.offset) { index, source in
                    HStack(spacing: 6) {
                        Text("[\(index + 1)]")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                        Text(source.site)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { NSWorkspace.shared.open(source.url) }
                }
            }
        }
    }

    private var footer: String {
        if card.isPlan, card.dive != nil { return "Hover a step for the line on the page it fixes · click a source to open it" }
        guard let dive = card.dive else { return "Google Search, through Gemini" }
        let searched = dive.searches.first.map { "Searched \u{201C}\($0)\u{201D}" } ?? "Google Search"
        return "\(searched) · click a finding or source to open it"
    }
}
