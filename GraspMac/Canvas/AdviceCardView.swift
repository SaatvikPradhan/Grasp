import GraspKit
import SwiftUI

/// What to say to the dealer, numbered, in big type you can read off the laptop.
struct AdviceCardView: View {
    let advice: Advice

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("WHAT TO SAY")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Label("read aloud", systemImage: "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }

            ForEach(Array(advice.lines.enumerated()), id: \.offset) { number, line in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(number + 1)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.paper)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Theme.accent))
                    Text(line)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
            Text(advice.isFromAI ? "Worded by Gemini · every number computed by Grasp" : "Grasp's talking points · every number computed by Grasp")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
        }
    }
}

/// What the salesperson said, each claim checked against the paper.
struct PitchCardView: View {
    let checks: [PitchCheck]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("THE PITCH, CHECKED")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Label("listening with consent", systemImage: "ear")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }

            // The latest three; the newest first.
            ForEach(checks.suffix(3).reversed()) { check in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(check.heard)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text(verdict(check.verdict))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.paper)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(color(check.verdict)))
                    }
                    Text(check.note)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func verdict(_ verdict: PitchCheck.Verdict) -> String {
        switch verdict {
        case .holds: "CHECKS OUT"
        case .catch: "CATCH"
        case .pressure: "PRESSURE"
        }
    }

    private func color(_ verdict: PitchCheck.Verdict) -> Color {
        switch verdict {
        case .holds: Theme.accent
        case .catch: Theme.hot
        case .pressure: Theme.warn
        }
    }
}
