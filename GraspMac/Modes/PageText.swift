import Foundation
import GraspKit
@preconcurrency import Vision

/// Apple's on-device text recognition, used to put boxes around what Gemini read.
/// Gemini says what the numbers are; Vision says where they are on the page.
enum PageText {
    /// Every line of text on the photo, with a way to box any part of it.
    static func recognize(jpeg: Data) async -> [VNRecognizedText] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                try? VNImageRequestHandler(data: jpeg).perform([request])
                continuation.resume(returning: (request.results ?? []).compactMap { $0.topCandidates(1).first })
            }
        }
    }

    /// Boxes, in the phone's coordinates, around each term and add-on found on the page.
    static func highlights(for reading: OfferReading, in lines: [VNRecognizedText]) -> [LinkHighlight] {
        HighlightMatcher.matches(in: lines.map(\.string), for: reading).compactMap { match in
            let line = lines[match.line]
            guard let box = try? line.boundingBox(for: match.range)?.boundingBox else { return nil }
            // Vision's origin is the bottom left; the phone draws from the top left.
            return LinkHighlight(
                text: String(line.string[match.range]),
                rect: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height),
                kind: match.kind
            )
        }
    }
}
