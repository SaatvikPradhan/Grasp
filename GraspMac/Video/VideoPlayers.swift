import AppKit
import AVFoundation
import GraspKit
import Observation

/// One player per video on the canvas, so a moment, a fact or a note can jump to its time, and a
/// note can be stamped with where the video is. YouTube videos open in the browser instead.
@MainActor @Observable
final class VideoPlayers {
    static let shared = VideoPlayers()

    @ObservationIgnored private var players: [UUID: AVPlayer] = [:]
    @ObservationIgnored private var frames: [FrameKey: NSImage] = [:]

    /// The player for a video file; nil for YouTube.
    func player(for document: PageDocument) -> AVPlayer? {
        guard case .file(let url)? = document.video?.location else { return nil }
        if let player = players[document.id] { return player }
        let player = AVPlayer(url: url)
        players[document.id] = player
        return player
    }

    /// Jumps to a moment and plays from there.
    func seek(_ document: PageDocument, to seconds: Double) {
        if let player = player(for: document) {
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
        } else if let url = document.video?.webURL(at: seconds) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Where a video file is now, for stamping notes; nil for YouTube or before it has played.
    func currentTime(of document: PageDocument) -> Double? {
        guard let player = players[document.id] else { return nil }
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : nil
    }

    /// The frame nearest a moment, from those made ahead with `prepareFrames`, or the thumbnail.
    func frame(of document: PageDocument, at seconds: Double) -> NSImage? {
        let made = frames.filter { $0.key.id == document.id && abs($0.key.seconds - seconds) <= 3 }
        return made.min { abs($0.key.seconds - seconds) < abs($1.key.seconds - seconds) }?.value ?? document.image
    }

    /// Makes the frames hovers will show: each moment's, and each fact's.
    func prepareFrames(of document: PageDocument, at times: [Double]) async {
        guard case .file(let url)? = document.video?.location else { return }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        // The exact frame, not the nearest keyframe (which can be many seconds earlier).
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        for seconds in Set(times) {
            // Times are whole seconds, and a slide changes as its words start: look a moment in.
            guard let (image, _) = try? await generator.image(at: CMTime(seconds: seconds + 1.5, preferredTimescale: 600)) else { continue }
            frames[FrameKey(id: document.id, seconds: seconds)] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }

    private struct FrameKey: Hashable {
        var id: UUID
        var seconds: Double
    }
}
