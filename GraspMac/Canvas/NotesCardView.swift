import GraspKit
import SwiftUI

/// Notes on a paper, each marked by whether the paper backs it (hover one to see the passage),
/// and where the research could go next, each from something the paper leaves open.
struct NotesCardView: View {
    let cardID: UUID
    let card: NotesCard

    private var notes: [LinkedNotes.Note] { card.linked.notes }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR NOTES, CHECKED AGAINST THE PAPER")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text(card.paperTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(tally)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }

            ForEach(Array(notes.enumerated()), id: \.offset) { index, note in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Image(systemName: symbol(note.status))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(color(note.status))
                            .frame(width: 16)
                        Text(note.note)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        if note.status == .notInPaper {
                            Text("not in the paper")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                                .fixedSize()
                        }
                    }
                    if let says = note.paperSays {
                        Text("Paper: \(says)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.hot)
                            .lineLimit(1)
                            .padding(.leading, 24)
                    }
                }
                .frame(height: note.paperSays == nil ? 22 : 40, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(PassageHover(target: note.location == nil ? nil : .passage(card: cardID, index: index)))
            }

            if !card.linked.directions.isEmpty {
                Text("WHERE THIS COULD GO")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 4)
                ForEach(Array(card.linked.directions.enumerated()), id: \.offset) { index, direction in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(direction.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text(direction.why)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    .frame(height: 38, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hoverSource(.passage(card: cardID, index: notes.count + index))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var tally: String {
        let matching = notes.filter { $0.status == .matches }.count
        let differing = notes.filter { $0.status == .differs }.count
        let missing = notes.filter { $0.status == .notInPaper }.count
        var parts = ["\(matching) match the paper"]
        if differing > 0 { parts.append("\(differing) differ") }
        if missing > 0 { parts.append("\(missing) not in it") }
        return parts.joined(separator: " · ") + " · hover a note to see the passage"
    }

    private func symbol(_ status: LinkedNotes.Note.Status) -> String {
        switch status {
        case .matches: "checkmark.circle.fill"
        case .differs: "exclamationmark.triangle.fill"
        case .notInPaper: "questionmark.circle"
        }
    }

    private func color(_ status: LinkedNotes.Note.Status) -> Color {
        switch status {
        case .matches: Theme.accent
        case .differs: Theme.hot
        case .notInPaper: Theme.muted
        }
    }
}

/// Hover for a note that has a passage; nothing for one that doesn't.
private struct PassageHover: ViewModifier {
    let target: HoverTarget?

    func body(content: Content) -> some View {
        if let target {
            content.hoverSource(target)
        } else {
            content
        }
    }
}
