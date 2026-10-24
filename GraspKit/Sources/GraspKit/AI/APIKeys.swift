import Foundation

/// Keys from `Config/Secrets.xcconfig`, which the build copies into the app's Info.plist.
public enum APIKeys {
    public static var gemini: String? { value(for: "GEMINI_API_KEY") }
    public static var elevenLabs: String? { value(for: "ELEVENLABS_API_KEY") }

    private static func value(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        // Empty when Secrets.xcconfig is missing; the placeholder when it was copied but not filled in.
        guard !trimmed.isEmpty, !trimmed.hasPrefix("your-") else { return nil }
        return trimmed
    }
}
