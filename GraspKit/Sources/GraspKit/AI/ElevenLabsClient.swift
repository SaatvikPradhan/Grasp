import Foundation

/// Grasp's voice: ElevenLabs text to speech, returned as MP3.
public struct ElevenLabsClient: Sendable {
    /// "Sarah – mature, reassuring, confident", a premade voice every account has.
    public static let voiceID = "EXAVITQu4vr4xnSDxMaL"
    /// About 0.7 s for a sentence (Oct 24); the v4 models sounded similar but took 1.2 s.
    public static let model = "eleven_flash_v2_5"

    public var apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// A client using the key from the app's Info.plist, or nil when none is set.
    public static var fromAppKeys: ElevenLabsClient? {
        APIKeys.elevenLabs.map(ElevenLabsClient.init)
    }

    public func speech(for text: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(Self.voiceID)?output_format=mp3_44100_128")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        // The fast model misreads digits ("$27,956", "8.9%"), so numbers go in as words.
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": SpokenText.words(text), "model_id": Self.model])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw GeminiClient.Failure.http(status: status, message: "ElevenLabs: " + String(decoding: data.prefix(300), as: UTF8.self))
        }
        return data
    }
}
