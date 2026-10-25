@preconcurrency import AVFoundation
import Observation
@preconcurrency import Speech

/// The microphone through Apple's speech recognizer, on device when the Mac supports it.
/// `start()` when the talk key goes down, `stop` when it comes up.
@MainActor @Observable
final class SpeechListener {
    enum Availability: Equatable {
        case unknown, ready
        case unavailable(String)
    }

    private(set) var availability = Availability.unknown
    private(set) var isListening = false
    /// What has been heard so far, updated as you speak.
    private(set) var transcript = ""

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var finish: ((String) -> Void)?

    /// Asks for speech recognition and the microphone.
    func prepare() async {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            availability = .unavailable("Speech recognition is off. Turn it on in System Settings › Privacy & Security › Speech Recognition.")
            return
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            availability = .unavailable("The microphone is off. Turn it on in System Settings › Privacy & Security › Microphone.")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            availability = .unavailable("Speech recognition isn't available right now.")
            return
        }
        availability = .ready
    }

    func start() {
        guard availability == .ready, !isListening, let recognizer else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            availability = .unavailable("No microphone found.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Not forced on device: that fails silently when the Mac hasn't downloaded the speech model.
        // Words Grasp listens for, so they win over sound-alikes.
        request.contextualStrings = ["Grasp", "months", "credit union", "compare", "APR", "temperatures", "fit it", "export"]

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            availability = .unavailable("Couldn't start the microphone: \(error.localizedDescription)")
            return
        }

        transcript = ""
        self.request = request
        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? (error != nil)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.received(text, isFinal: isFinal) }
            }
        }
    }

    /// Stops listening and hands `completion` the final transcript, which may be empty.
    func stop(completion: @escaping (String) -> Void) {
        guard isListening else {
            completion("")
            return
        }
        isListening = false
        finish = completion
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        // The recognizer normally sends a final result within moments; don't wait forever.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.deliver()
        }
    }

    private func received(_ text: String?, isFinal: Bool) {
        if let text, !text.isEmpty { transcript = text }
        if isFinal, !isListening { deliver() }
    }

    private func deliver() {
        guard let finish else { return }
        self.finish = nil
        task?.cancel()
        task = nil
        request = nil
        finish(transcript)
    }
}
