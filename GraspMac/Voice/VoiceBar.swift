import GraspKit
import SwiftUI

/// Bottom center of the canvas: what Grasp is hearing, and what it did about it.
struct VoiceBar: View {
    let voice: VoiceController
    let money: MoneyMode
    let asker: Asker
    let lab: LabSession

    @Environment(\.isCanvasSnapshot) private var isSnapshot
    @FocusState private var typingFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            if lab.isRecording {
                // Always visible while recording: everyone at the bench can see it.
                HStack(spacing: 6) {
                    Circle().fill(Theme.warn).frame(width: 8, height: 8)
                    Text("Taking lab notes \(clockTime(lab.elapsed))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.warn)
                    // What it just heard, so you can see the mic is working.
                    Text(lab.lastHeard.isEmpty ? "listening…" : "\u{201C}\(lab.lastHeard)\u{201D}")
                        .font(.system(size: 12).italic())
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .frame(maxWidth: 260, alignment: .leading)
                }
                .padding(.trailing, 4)
            }
            if money.conversation.isOn {
                // Always visible while listening: everyone agreed, and everyone can see it.
                HStack(spacing: 6) {
                    Circle().fill(Theme.warn).frame(width: 8, height: 8)
                    Text("Hearing the pitch")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.warn)
                }
                .padding(.trailing, 4)
            }
            if money.voiceOut.isSpeaking {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            } else if money.isWritingAdvice || asker.isAnswering || lab.isWriting {
                ProgressView().controlSize(.small)
            }
            icon
            text
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Theme.surface.opacity(voice.phase == .idle ? 0.6 : 0.95)))
        .overlay(Capsule().stroke(voice.phase == .listening ? Theme.hot : voice.phase == .typing ? Theme.accent : Theme.line,
                                 lineWidth: voice.phase == .listening || voice.phase == .typing ? 2 : 1))
        .animation(.spring(duration: 0.25), value: voice.phase)
        .contentShape(Capsule())
        // A click on the quiet bar types instead of talking.
        .onTapGesture { if voice.phase == .idle { voice.beginTyping() } }
        .allowsHitTesting(voice.phase == .idle || voice.phase == .typing)
    }

    /// The typing field. Snapshots can't draw a text field, so they show the text instead.
    @ViewBuilder
    private var typingField: some View {
        if isSnapshot {
            Text(voice.typed.isEmpty ? "Ask a question or say what to do…" : voice.typed + "▏")
                .foregroundStyle(voice.typed.isEmpty ? Theme.muted : Theme.ink)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 420, alignment: .leading)
        } else {
            TextField("Ask a question or say what to do…", text: Bindable(voice).typed)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 420)
                .focused($typingFocused)
                .onAppear { typingFocused = true }
                .onSubmit { voice.submitTyped() }
                .onExitCommand { voice.cancelTyping() }
                // Clicking away from an empty field closes it.
                .onChange(of: typingFocused) { _, focused in
                    if !focused, voice.typed.isEmpty { voice.cancelTyping() }
                }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch voice.phase {
        case .idle:
            Image(systemName: "mic").foregroundStyle(Theme.muted)
        case .listening:
            Image(systemName: "mic.fill")
                .foregroundStyle(Theme.hot)
                .symbolEffect(.pulse, options: .repeating)
        case .typing:
            Image(systemName: "keyboard").foregroundStyle(Theme.accent)
        case .thinking:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
        }
    }

    @ViewBuilder
    private var text: some View {
        switch voice.phase {
        case .idle:
            Text("Make a fist to talk · hold Space · ⌘K to type")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        case .typing:
            typingField
        case .listening:
            Text(voice.listener.transcript.isEmpty ? "Listening… open your hand to send" : voice.listener.transcript)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        case .thinking(let heard):
            Text("“\(heard)”")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        case .done(let heard, let result):
            HStack(spacing: 8) {
                Text("“\(heard)”").foregroundStyle(Theme.muted).lineLimit(1)
                Image(systemName: "arrow.right").foregroundStyle(Theme.muted)
                Text(result).foregroundStyle(Theme.ink).fontWeight(.semibold)
            }
            .font(.system(size: 15))
        case .failed(let reason):
            Text(reason)
                .font(.system(size: 13))
                .foregroundStyle(Theme.warn)
                .lineLimit(2)
        }
    }
}
