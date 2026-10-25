import SwiftUI

/// Bottom center of the canvas: what Grasp is hearing, and what it did about it.
struct VoiceBar: View {
    let voice: VoiceController
    let money: MoneyMode
    let asker: Asker

    var body: some View {
        HStack(spacing: 10) {
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
            } else if money.isWritingAdvice || asker.isAnswering {
                ProgressView().controlSize(.small)
            }
            icon
            text
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Theme.surface.opacity(voice.phase == .idle ? 0.6 : 0.95)))
        .overlay(Capsule().stroke(voice.phase == .listening ? Theme.hot : Theme.line, lineWidth: voice.phase == .listening ? 2 : 1))
        .animation(.spring(duration: 0.25), value: voice.phase)
        .allowsHitTesting(false)
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
            Text("Make a fist to talk · or hold Space")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
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
