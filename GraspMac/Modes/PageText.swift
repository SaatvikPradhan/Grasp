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

    /// Where each whole line is on the photo: normalized, origin at the top left.
    static func lineBoxes(_ lines: [VNRecognizedText]) -> [CGRect] {
        lines.map { line in
            guard let box = try? line.boundingBox(for: line.string.startIndex..<line.string.endIndex)?.boundingBox else { return .zero }
            return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        }
    }

    /// Where each fact (by key) and catch (by title) of a reading is on the photo: normalized,
    /// origin at the top left.
    static func sources(for reading: PageReading, in lines: [VNRecognizedText]) -> (facts: [String: CGRect], catches: [String: CGRect]) {
        let strings = lines.map(\.string)
        func box(printed: String?, quote: String) -> CGRect? {
            guard let found = SourceLocator.locate(printed: printed, quote: quote, in: strings) else { return nil }
            var boxes: [CGRect] = []
            if let first = try? lines[found.line].boundingBox(for: found.range)?.boundingBox {
                boxes.append(first)
            }
            for extra in stride(from: found.line + 1, through: min(found.line + found.extraLines, lines.count - 1), by: 1) {
                let line = lines[extra]
                if let whole = try? line.boundingBox(for: line.string.startIndex..<line.string.endIndex)?.boundingBox {
                    boxes.append(whole)
                }
            }
            guard let union = boxes.dropFirst().reduce(boxes.first, { $0?.union($1) }) else { return nil }
            // Vision's origin is the bottom left.
            return CGRect(x: union.minX, y: 1 - union.maxY, width: union.width, height: union.height)
        }
        var facts: [String: CGRect] = [:]
        for fact in reading.facts {
            facts[fact.key] = box(printed: fact.asPrinted, quote: fact.quote)
        }
        var catches: [String: CGRect] = [:]
        for item in reading.allCatches {
            catches[item.title] = box(printed: item.printed, quote: item.quote)
        }
        return (facts, catches)
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
