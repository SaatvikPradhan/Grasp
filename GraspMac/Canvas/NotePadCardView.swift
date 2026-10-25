import GraspKit
import SwiftUI

/// Notes typed right on the canvas, beside the page they're about, one per line. Checking links
/// each line to the page and marks whether the page backs it; "take a note…" adds a line by voice.
struct NotePadCardView: View {
    let cardID: UUID
    let card: NotePadCard

    @Environment(CanvasModel.self) private var canvas
    @Environment(\.isCanvasSnapshot) private var isSnapshot
    @State private var text = ""
    @FocusState private var editing: Bool

    /// The video the notes are on, if they're on one: each new line gets where it's playing.
    private var video: PageDocument? {
        card.documentID.flatMap { canvas.documents[$0] }.flatMap { $0.video == nil ? nil : $0 }
    }

    /// "[0:36] ", where the video is now, once it has played.
    private var stamp: String? {
        guard let video, let seconds = VideoPlayers.shared.currentTime(of: video), seconds > 0.5 else { return nil }
        return "[\(VideoReading.clock(seconds))] "
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR NOTES")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text(card.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("One note per line. Type here, or say \u{201C}take a note\u{2026}\u{201D}")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 1)
                        .padding(.leading, 5)
                }
                if isSnapshot {
                    // Offscreen rendering can't draw a live text view.
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink)
                        .padding(.leading, 5)
                } else {
                    TextEditor(text: $text)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink)
                        .scrollContentBackground(.hidden)
                        .focused($editing)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.paper.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(editing ? Theme.accent : Theme.line, lineWidth: 1))

            HStack(spacing: 10) {
                Text(card.documentID == nil ? "Hand Grasp a page to check these against" : "\(card.lines.count) note\(card.lines.count == 1 ? "" : "s")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    editing = false
                    canvas.onCheckNotePad?(cardID)
                } label: {
                    Text(card.isChecking ? "Checking\u{2026}" : video == nil ? "Check against the page" : "Check against the video")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.paper)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .disabled(card.documentID == nil || card.lines.isEmpty || card.isChecking)
                .opacity(card.documentID == nil || card.lines.isEmpty ? 0.4 : 1)
            }
        }
        .onAppear {
            text = card.text
            if card.text.isEmpty { editing = true }
        }
        .onChange(of: text) { old, new in
            // A new line under a playing video starts with its time.
            if new.count == old.count + 1, new.hasSuffix("\n"), let stamp {
                text = new + stamp
                return
            }
            canvas.updateNotePad(cardID) { $0.text = text }
        }
        // A line added by voice.
        .onChange(of: card.text) { if card.text != text { text = card.text } }
        .onChange(of: editing) {
            canvas.isTyping = editing
            if editing, text.isEmpty, let stamp { text = stamp }
        }
        .onDisappear { if editing { canvas.isTyping = false } }
    }
}

private struct CanvasSnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Drawing the canvas to a PNG, where live AppKit views (text editors) can't be drawn.
    var isCanvasSnapshot: Bool {
        get { self[CanvasSnapshotKey.self] }
        set { self[CanvasSnapshotKey.self] = newValue }
    }
}
