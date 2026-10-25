import AppKit
import GraspKit
import ImageIO
import Observation
import UniformTypeIdentifiers

/// Reads the paper in front of you (contract, sticker, quote). Each photo lands on the
/// canvas as a scan card, Gemini reads it, and the card becomes a chart. Photos from the
/// phone also get their terms and add-ons boxed and sent back.
@MainActor @Observable
final class PaperReader {
    enum State: Equatable {
        case idle
        case reading
        case read(OfferReading, seconds: Double)
        /// Any other page, read by the general reader.
        case page(PageReading, seconds: Double)
        case failed(String)
    }

    /// The most recent read, for the panel.
    private(set) var state = State.idle
    private(set) var photo: NSImage?
    /// Called with boxes to draw on a phone capture once it has been read.
    @ObservationIgnored var onHighlights: ((UUID, [LinkHighlight]) -> Void)?

    @ObservationIgnored private let canvas: CanvasModel
    @ObservationIgnored private var latestCardID: UUID?

    init(canvas: CanvasModel) {
        self.canvas = canvas
    }

    /// Reads a photo. `captureID` is set for photos from the phone, so highlights can go back.
    func read(jpeg: Data, captureID: UUID? = nil) {
        guard let image = NSImage(data: jpeg) else {
            state = .failed("Couldn't open that image.")
            return
        }
        let cardID = canvas.addScan(image)
        latestCardID = cardID
        photo = image

        guard let client = GeminiClient.fromAppKeys else {
            let message = GeminiClient.Failure.missingKey.localizedDescription
            state = .failed(message)
            canvas.failScan(cardID, message: message)
            return
        }
        state = .reading
        let started = Date()

        Task {
            // Three readers at once: the car-offer reader (fast, drives the loan cards), the
            // general page reader (anything: facts, catches, model), and Vision (where the words are).
            async let lines = PageText.recognize(jpeg: jpeg)
            async let page = try? PageReader(client: client).read(jpeg: jpeg)
            let offer = try? await OfferReader(client: client).read(jpeg: jpeg)

            if let offer, offer.documentType != .other {
                if latestCardID == cardID {
                    state = .read(offer, seconds: Date().timeIntervalSince(started))
                }
                canvas.finishScan(cardID, with: offer)
                if let captureID {
                    onHighlights?(captureID, PageText.highlights(for: offer, in: await lines))
                }
            }

            guard let page = await page else {
                if offer == nil || offer?.documentType == .other {
                    let message = "Couldn't read that page. Try again with the whole page in view."
                    if latestCardID == cardID { state = .failed(message) }
                    canvas.failScan(cardID, message: message)
                }
                return
            }
            let recognized = await lines
            let sources = PageText.sources(for: page, in: recognized)
            let document = PageDocument(
                id: UUID(), image: image, reading: page,
                factBoxes: sources.facts, catchBoxes: sources.catches,
                text: recognized.map(\.string), lineBoxes: PageText.lineBoxes(recognized),
                captureID: captureID, readAt: Date()
            )
            canvas.finishPage(cardID, document: document)

            // Pages that aren't car offers get their catches (red) and facts (green) boxed on the phone.
            if offer == nil || offer?.documentType == .other {
                if latestCardID == cardID {
                    state = .page(page, seconds: Date().timeIntervalSince(started))
                }
                if let captureID {
                    let boxes = page.catches.compactMap { item in
                        sources.catches[item.title].map { LinkHighlight(text: item.title, rect: $0, kind: .addon) }
                    } + page.facts.compactMap { fact in
                        sources.facts[fact.key].map { LinkHighlight(text: fact.asPrinted, rect: $0, kind: .term) }
                    }
                    onHighlights?(captureID, boxes)
                }
            }
        }
    }

    /// Reads an image file, for testing without the phone (drop it on the canvas or press ⌘O).
    func read(fileAt url: URL) {
        guard let jpeg = Self.jpeg(at: url) else {
            state = .failed("Couldn't open \(url.lastPathComponent) as an image.")
            return
        }
        read(jpeg: jpeg)
    }

    /// Any image file as a JPEG at most 2000 px on its long side, the size the phone sends.
    private static func jpeg(at url: URL) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2000,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
