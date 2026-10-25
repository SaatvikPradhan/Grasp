@preconcurrency import AVFoundation
import GraspKit
import Observation

/// Grasp's voice out loud: ElevenLabs when there's a key, the Mac's own voice otherwise.
@MainActor @Observable
final class VoiceOut: NSObject {
    private(set) var isSpeaking = false

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private let fallback = AVSpeechSynthesizer()

    /// Snapshot runs (see GraspMacApp) stay quiet.
    private static let isMuted = ProcessInfo.processInfo.environment["GRASP_SNAPSHOT"] != nil

    func say(_ text: String) async {
        guard !Self.isMuted else { return }
        stop()
        isSpeaking = true
        if let client = ElevenLabsClient.fromAppKeys,
           let audio = try? await client.speech(for: text),
           let player = try? AVAudioPlayer(data: audio) {
            self.player = player
            player.delegate = self
            player.play()
        } else {
            fallback.delegate = self
            fallback.speak(AVSpeechUtterance(string: text))
        }
    }

    func stop() {
        player?.stop()
        player = nil
        fallback.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}

extension VoiceOut: AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
