import AppKit
import GraspKit
import ImageIO
import Observation
import UniformTypeIdentifiers

/// Sends a photo of the paper (contract, sticker, quote) to Gemini and puts the result on the canvas.
@MainActor @Observable
final class PaperReader {
    enum State: Equatable {
        case idle
        case reading
        case read(OfferReading, seconds: Double)
        case failed(String)
    }

    private(set) var state = State.idle
    private(set) var photo: NSImage?

    @ObservationIgnored private let canvas: CanvasModel
    @ObservationIgnored private var task: Task<Void, Never>?

    init(canvas: CanvasModel) {
        self.canvas = canvas
    }

    func read(jpeg: Data) {
        guard let client = GeminiClient.fromAppKeys else {
            state = .failed(GeminiClient.Failure.missingKey.localizedDescription)
            return
        }
        task?.cancel()
        photo = NSImage(data: jpeg)
        state = .reading
        let started = Date()
        task = Task {
            do {
                let reading = try await OfferReader(client: client).read(jpeg: jpeg)
                guard !Task.isCancelled else { return }
                state = .read(reading, seconds: Date().timeIntervalSince(started))
                canvas.showOffer(reading)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
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
