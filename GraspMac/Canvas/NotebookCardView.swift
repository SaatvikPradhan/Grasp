import GraspKit
import SwiftUI

/// A lab session written up: each step with what was said and what its cup's probe read (hover a
/// step for the camera frame), how the actions and readings connect, and what to try next.
struct NotebookCardView: View {
    let cardID: UUID
    let card: NotebookCard

    private var notebook: LabNotebook { card.notebook }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LAB NOTEBOOK · \(clockTime(notebook.duration)) RECORDED" + (card.isRehearsal ? " · REHEARSAL" : ""))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text(notebook.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(notebook.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            .frame(height: 66, alignment: .topLeading)

            HStack(alignment: .top, spacing: 20) {
                steps
                    .frame(width: Card.notebookStepsWidth, alignment: .topLeading)
                findings
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Spacer(minLength: 0)
            Text("⌘⇧E saves it with the readings, transcript, frames and Methods")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WHAT HAPPENED · hover for the camera frame")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .frame(height: 18, alignment: .leading)
            ForEach(Array(notebook.steps.enumerated()), id: \.offset) { index, step in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Text(clockTime(step.seconds))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 38, alignment: .leading)
                        Text(step.did)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let probe = probe(step) {
                            Text(probe)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(step.event == nil ? Theme.muted : Theme.hot)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    if let said = step.said {
                        Text("“\(said)”")
                            .font(.system(size: 12).italic())
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                            .padding(.leading, 46)
                    }
                }
                .frame(height: step.said == nil ? 20 : 34, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hoverSource(.labStep(card: cardID, index: index))
            }
        }
    }

    private var findings: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !notebook.observations.isEmpty {
                Text("WHAT IT SHOWS")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .frame(height: 18, alignment: .leading)
                ForEach(Array(notebook.observations.enumerated()), id: \.offset) { _, observation in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: observation.numbersChecked ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(observation.numbersChecked ? Theme.accent : Theme.hot)
                        Text(observation.text)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(3)
                    }
                    .frame(height: 50, alignment: .topLeading)
                }
            }
            if !notebook.next.isEmpty {
                Text("TRY NEXT")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .frame(height: 18, alignment: .leading)
                ForEach(notebook.next, id: \.self) { next in
                    Text("→ \(next)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .frame(height: 32, alignment: .topLeading)
                }
            }
        }
    }

    /// "B 68.2 °C · slowed" for a step on a cup.
    private func probe(_ step: LabNotebook.Step) -> String? {
        guard let cup = step.cup else { return nil }
        let reading = step.celsius.map { "\(cup.rawValue) \(String(format: "%.1f", $0)) °C" } ?? cup.rawValue
        guard let event = step.event else { return reading }
        return "\(reading) · \(event.kind.rawValue)"
    }
}
