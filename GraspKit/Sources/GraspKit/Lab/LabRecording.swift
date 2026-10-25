import Foundation

/// What a lab session recorded: camera frames, what people said and the probe readings, each
/// stamped with seconds since the session started.
public struct LabRecording: Sendable {
    public struct Frame: Sendable {
        public var seconds: Double
        public var jpeg: Data

        public init(seconds: Double, jpeg: Data) {
            self.seconds = seconds
            self.jpeg = jpeg
        }
    }

    /// Something said, as one line.
    public struct Line: Equatable, Sendable {
        public var seconds: Double
        public var text: String

        public init(seconds: Double, text: String) {
            self.seconds = seconds
            self.text = text
        }
    }

    public var frames: [Frame]
    public var speech: [Line]
    /// Probe readings, `time` in seconds since the start.
    public var readings: [Reading]
    public var duration: Double
    /// The protocol followed, when the run was guided.
    public var protocolRecord: ProtocolRecord?

    public init(frames: [Frame], speech: [Line], readings: [Reading], duration: Double, protocolRecord: ProtocolRecord? = nil) {
        self.frames = frames
        self.speech = speech
        self.readings = readings
        self.duration = duration
        self.protocolRecord = protocolRecord
    }
}

/// "1:05" for 65 seconds.
public func clockTime(_ seconds: Double) -> String {
    let whole = max(0, Int(seconds.rounded()))
    return "\(whole / 60):" + String(format: "%02d", whole % 60)
}

/// Turns the speech recognizer's growing transcript into timed lines. The recognizer reports the
/// whole session's text each time it grows, and starts a new session about once a minute, so each
/// word is stamped with when it first appeared and lines break where people paused.
public struct TranscriptBuilder: Sendable {
    struct Word: Sendable {
        var text: String
        var seconds: Double
    }

    private var finished: [[Word]] = []
    private var current: [Word] = []

    public init() {}

    /// The recognizer starts each session over from nothing: keep what the last one heard.
    public mutating func endSession() {
        if !current.isEmpty { finished.append(current) }
        current = []
    }

    public mutating func heard(_ text: String, at seconds: Double) {
        let words = text.split(separator: " ").map(String.init)
        // A new session the listener didn't announce starts over with a much shorter text.
        if current.count >= 3, words.count < current.count / 2 {
            finished.append(current)
            current = []
        }
        current = words.enumerated().map { index, word in
            Word(text: word, seconds: index < current.count ? current[index].seconds : seconds)
        }
    }

    /// Lines, broken at pauses of `pause` seconds or more.
    public func lines(pause: Double = 1.5) -> [LabRecording.Line] {
        (finished + [current]).flatMap { words -> [LabRecording.Line] in
            var lines: [LabRecording.Line] = []
            var text: [String] = []
            var start = 0.0, last = -Double.infinity
            for word in words {
                if !text.isEmpty, word.seconds - last >= pause {
                    lines.append(LabRecording.Line(seconds: start, text: text.joined(separator: " ")))
                    text = []
                }
                if text.isEmpty { start = word.seconds }
                text.append(word.text)
                last = word.seconds
            }
            if !text.isEmpty { lines.append(LabRecording.Line(seconds: start, text: text.joined(separator: " "))) }
            return lines
        }
    }
}
