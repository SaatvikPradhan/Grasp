import Foundation
import Testing
@testable import GraspKit

struct LinkMessageTests {
    @Test func frameSurvivesTheTrip() throws {
        let jpeg = Data((0..<50_000).map { UInt8(truncatingIfNeeded: $0) })
        let message = LinkMessage.frame(LinkFrame(jpeg: jpeg, purpose: .capture, sentAt: 1234.5, roundTripMs: 42))
        #expect(try LinkMessage.decoded(from: message.encoded()) == message)
    }

    @Test func jpegIsNotInflated() throws {
        // Base64 would add a third; a binary plist adds a small fixed header.
        let jpeg = Data(count: 60_000)
        let data = try LinkMessage.frame(LinkFrame(jpeg: jpeg, purpose: .live, sentAt: 0)).encoded()
        #expect(data.count < jpeg.count + 500)
    }

    @Test func receiptSurvivesTheTrip() throws {
        let message = LinkMessage.received(frameID: UUID(), sentAt: 99.25)
        #expect(try LinkMessage.decoded(from: message.encoded()) == message)
    }
}
