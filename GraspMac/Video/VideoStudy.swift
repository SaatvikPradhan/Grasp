import AppKit
import AVFoundation
import GraspKit
import Observation
import UniformTypeIdentifiers

/// Reads a video like a page. A lecture file or a YouTube link lands on the canvas while Gemini
/// watches it, then becomes a card with the player, the moments worth jumping to, and the facts
/// said, each at its time. Ask, notes, deep dives and Tiger Data then treat it like any page.
@MainActor @Observable
final class VideoStudy {
    private(set) var isReading = false
    /// Called with every video read, after its card is on the canvas.
    @ObservationIgnored var onPage: ((PageDocument) -> Void)?

    @ObservationIgnored private let canvas: CanvasModel

    /// Videos smaller than this go in the request; bigger ones are uploaded first.
    static let inlineLimit = 15_000_000

    init(canvas: CanvasModel) {
        self.canvas = canvas
    }

    func read(fileAt url: URL) {
        Task {
            let asset = AVURLAsset(url: url)
            let duration = try? await asset.load(.duration).seconds
            let thumbnail = await Self.thumbnail(of: asset) ?? Self.placeholder
            let cardID = canvas.addScan(thumbnail, label: "Watching the video\u{2026}")
            await read(cardID: cardID, image: thumbnail, location: .file(url), duration: duration) { client in
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "video/mp4"
                guard data.count >= Self.inlineLimit else { return .inline(data, mimeType: type) }
                return try await client.upload(data, mimeType: type, name: url.lastPathComponent)
            }
        }
    }

    /// Reads a public YouTube video, which Gemini watches itself. Returns a line for the voice bar.
    @discardableResult
    func read(youTube link: String) -> String {
        guard let id = VideoSource.youTubeID(in: link), let url = URL(string: "https://www.youtube.com/watch?v=\(id)") else {
            return "That isn't a YouTube link"
        }
        Task {
            let thumbnail = await Self.youTubeThumbnail(id) ?? Self.placeholder
            let cardID = canvas.addScan(thumbnail, label: "Watching the video\u{2026}")
            await read(cardID: cardID, image: thumbnail, location: .youTube(id: id), duration: nil) { _ in .youTube(url) }
        }
        return "Watching the video"
    }

    /// Asks for a YouTube link.
    func openLinkByTyping() {
        let alert = NSAlert()
        alert.messageText = "Study a YouTube video"
        alert.informativeText = "Paste the link to a public video. Grasp watches it, marks the moments, and your notes link to times."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = "https://www.youtube.com/watch?v=…"
        if let copied = NSPasteboard.general.string(forType: .string), VideoSource.youTubeID(in: copied) != nil {
            field.stringValue = copied
        }
        alert.accessoryView = field
        alert.addButton(withTitle: "Watch It")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        read(youTube: field.stringValue)
    }

    private func read(cardID: UUID, image: NSImage, location: VideoSource.Location, duration: Double?,
                      media: (GeminiClient) async throws -> GeminiClient.Media) async {
        guard let client = GeminiClient.fromAppKeys else {
            canvas.failScan(cardID, message: GeminiClient.Failure.missingKey.localizedDescription)
            return
        }
        isReading = true
        defer { isReading = false }
        do {
            let video = try await VideoReader(client: client).read(try await media(client), duration: duration)
            guard !video.transcript.isEmpty else {
                canvas.failScan(cardID, message: "Couldn't hear anything said in that video.")
                return
            }
            let document = PageDocument(id: UUID(), image: image, reading: video.page, factBoxes: [:], catchBoxes: [:],
                                        text: video.lines, lineBoxes: [], captureID: nil, readAt: Date(),
                                        video: VideoSource(location: location, duration: duration, reading: video))
            let times = video.moments.map(\.seconds) + video.facts.compactMap { video.seconds(of: $0.quote) }
            await VideoPlayers.shared.prepareFrames(of: document, at: times)
            canvas.finishVideo(cardID, document: document)
            onPage?(document)
        } catch {
            canvas.failScan(cardID, message: "Couldn't watch it: \(error.localizedDescription)")
        }
    }

    private static func thumbnail(of asset: AVURLAsset) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        guard let (image, _) = try? await generator.image(at: CMTime(seconds: 2, preferredTimescale: 600)) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private static func youTubeThumbnail(_ id: String) async -> NSImage? {
        guard let url = URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg"),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return NSImage(data: data)
    }

    /// A dark frame with a play sign, when there's no picture yet.
    private static let placeholder = NSImage(size: NSSize(width: 640, height: 360), flipped: false) { rect in
        NSColor(calibratedWhite: 0.1, alpha: 1).setFill()
        rect.fill()
        let play = NSImage(systemSymbolName: "play.rectangle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 90, weight: .regular))
        play?.draw(in: NSRect(x: rect.midX - 60, y: rect.midY - 45, width: 120, height: 90))
        return true
    }
}
