import AppKit
import GraspKit

/// ⌘V on the canvas: a YouTube link is studied, a copied photo or screenshot is read like a scanned
/// page, and a file copied in Finder (a photo or a video) is read as if it were dropped. While a
/// note is being typed, or in a dialog, ⌘V pastes text as usual.
@MainActor
final class CanvasPaste {
    private var monitor: Any?

    func install(paper: PaperReader, videos: VideoStudy) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "v",
                  !(event.window is NSPanel),
                  !((event.window?.firstResponder as? NSTextView)?.isEditable ?? false) else { return event }
            return MainActor.assumeIsolated {
                Self.paste(from: .general, paper: paper, videos: videos) ? nil : event
            }
        }
    }

    /// Reads what's on `pasteboard`. Returns false when there's nothing Grasp can read there.
    @discardableResult
    static func paste(from pasteboard: NSPasteboard, paper: PaperReader, videos: VideoStudy) -> Bool {
        if let file = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first {
            GraspMacApp.read(file, paper: paper, videos: videos)
            return true
        }
        if let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           VideoSource.youTubeID(in: text) != nil {
            videos.read(youTube: text)
            return true
        }
        if let image = NSImage(pasteboard: pasteboard), let jpeg = Self.jpeg(image) {
            paper.read(jpeg: jpeg)
            return true
        }
        return false
    }

    /// A pasted image as a JPEG at most 2000 px on its long side, the size the phone sends.
    private static func jpeg(_ image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, 2000 / Double(max(cgImage.width, cgImage.height, 1)))
        let width = Int(Double(cgImage.width) * scale), height = Int(Double(cgImage.height) * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
