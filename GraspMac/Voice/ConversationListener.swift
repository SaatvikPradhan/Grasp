@preconcurrency import AVFoundation
import Observation
@preconcurrency import Speech

/// Listens to the whole conversation (only with everyone's consent) and hands over the
/// transcript as it grows. Recognition sessions end after about a minute, so it keeps
/// starting new ones while it's on.
@MainActor @Observable
final class ConversationListener {
    private(set) var isOn = false

    /// Called with the current session's transcript every time it grows.
    @ObservationIgnored var onText: ((String) -> Void)?

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let feed = RequestFeed()
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    /// Returns why it couldn't start, or nil once listening.
    func start() -> String? {
        guard !isOn else { return nil }
        guard let recognizer, recognizer.isAvailable else { return "Speech recognition isn't available right now." }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { return "No microphone found." }

        let feed = self.feed
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            feed.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return "Couldn't start the microphone: \(error.localizedDescription)"
        }
        isOn = true
        beginSession()
        return nil
    }

    func stop() {
        isOn = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        feed.swap(nil)?.endAudio()
        task?.cancel()
        task = nil
    }

    private func beginSession() {
        guard isOn, let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        feed.swap(request)?.endAudio()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let ended = (result?.isFinal ?? false) || error != nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.isOn else { return }
                    if let text, !text.isEmpty { self.onText?(text) }
                    if ended { self.restartSoon() }
                }
            }
        }
    }

    /// A short pause first, so a recognizer that keeps failing doesn't spin.
    private func restartSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            self?.beginSession()
        }
    }
}

/// The current recognition request, shared with the audio thread that feeds it.
private final class RequestFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { request }?.append(buffer)
    }

    /// Replaces the request and returns the old one.
    func swap(_ new: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.withLock {
            let old = request
            request = new
            return old
        }
    }
}
