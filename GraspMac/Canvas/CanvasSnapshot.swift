import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders the canvas to a PNG, for Devpost screenshots (⌘⇧S saves to the Desktop).
/// Live camera previews don't render; everything else does.
enum CanvasSnapshot {
    @MainActor
    static func save<Content: View>(_ content: Content, size: CGSize, to url: URL) -> Bool {
        // The window asks for dark mode; a renderer has no window, so ask here too.
        let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height).environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    static var desktopURL: URL {
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Desktop/Grasp \(stamp).png")
    }
}
