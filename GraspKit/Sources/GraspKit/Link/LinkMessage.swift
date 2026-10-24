import Foundation

/// A camera frame from the phone.
public struct LinkFrame: Codable, Sendable, Equatable {
    public enum Purpose: String, Codable, Sendable {
        /// Small viewfinder frames, a few a second.
        case live
        /// A sharp frame taken on demand, for reading.
        case capture
    }

    public var id: UUID
    public var jpeg: Data
    public var purpose: Purpose
    /// The sender's clock when it sent the frame. The receiver echoes it back so the
    /// sender can time the round trip without the two clocks agreeing.
    public var sentAt: Double
    /// The sender's latest round trip, so the receiver can show it too.
    public var roundTripMs: Double?

    public init(id: UUID = UUID(), jpeg: Data, purpose: Purpose, sentAt: Double, roundTripMs: Double? = nil) {
        self.id = id
        self.jpeg = jpeg
        self.purpose = purpose
        self.sentAt = sentAt
        self.roundTripMs = roundTripMs
    }
}

/// Everything the phone and the Mac say to each other over `MultipeerLink`.
public enum LinkMessage: Codable, Sendable, Equatable {
    /// Phone → Mac.
    case frame(LinkFrame)
    /// Mac → phone, as soon as a frame arrives.
    case received(frameID: UUID, sentAt: Double)

    /// Binary property lists carry the JPEG bytes as they are, where JSON would base64 them.
    public func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> LinkMessage {
        try PropertyListDecoder().decode(LinkMessage.self, from: data)
    }
}
