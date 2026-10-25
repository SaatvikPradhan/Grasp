import AppKit
import AVFoundation
import GraspKit

/// A run's frames as a video: each frame held a quarter of a second, fitted into 1280 × 720, with a
/// caption bar along the bottom (the time, what was being done, each cup's reading then).
enum TimeLapse {
    static let size = CGSize(width: 1280, height: 720)
    /// Video frames a second: a frame taken every 4 s plays 16 times faster than the run.
    static let framesPerSecond: Int32 = 4

    enum Failure: LocalizedError {
        case noFrames
        case writer(String)

        var errorDescription: String? {
            switch self {
            case .noFrames: "There are no camera frames to make a time-lapse from."
            case .writer(let message): "Couldn't write the time-lapse: \(message)"
            }
        }
    }

    static func write(_ frames: [LabRecording.Frame], captions: (Double) -> String, to url: URL) async throws {
        let images = frames.compactMap { frame in
            NSImage(data: frame.jpeg)?.cgImage(forProposedRect: nil, context: nil, hints: nil).map { (frame.seconds, $0) }
        }
        guard !images.isEmpty else { throw Failure.noFrames }
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        guard writer.canAdd(input) else { throw Failure.writer("the video track") }
        writer.add(input)
        guard writer.startWriting() else { throw Failure.writer(writer.error?.localizedDescription ?? "couldn't start") }
        writer.startSession(atSourceTime: .zero)

        for (index, (seconds, image)) in images.enumerated() {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool else { throw Failure.writer("no pixel buffers") }
            var made: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
            guard let buffer = made else { throw Failure.writer("no pixel buffer") }
            draw(image, caption: captions(seconds), into: buffer)
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: framesPerSecond))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw Failure.writer(writer.error?.localizedDescription ?? "unfinished") }
    }

    /// The frame fitted into the video, black around it, and the caption bar along the bottom.
    private static func draw(_ image: CGImage, caption: String, into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return }
        context.setFillColor(.black)
        context.fill(CGRect(origin: .zero, size: size))
        let scale = min(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        let fitted = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.draw(image, in: CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2,
                                       width: fitted.width, height: fitted.height))

        let bar = CGRect(x: 0, y: 0, width: size.width, height: 64)
        context.setFillColor(CGColor(gray: 0, alpha: 0.65))
        context.fill(bar)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let text = NSAttributedString(string: caption, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 26, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
        text.draw(with: CGRect(x: 28, y: 18, width: size.width - 56, height: 34), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        NSGraphicsContext.restoreGraphicsState()
    }
}
