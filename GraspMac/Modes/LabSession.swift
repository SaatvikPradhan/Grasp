import AppKit
import GraspKit
import Observation

/// Lab notes, taken for you: while it records, a camera frame every few seconds (the phone's,
/// or the Mac's), what people say and every probe reading. Stopping writes the notebook: what was
/// done, what was said, what each probe did then, and how they connect.
@MainActor @Observable
final class LabSession {
    private(set) var isRecording = false
    private(set) var isWriting = false
    /// Seconds since recording started.
    private(set) var elapsed = 0.0

    @ObservationIgnored private let canvas: CanvasModel
    @ObservationIgnored private let probes: ProbeHub
    @ObservationIgnored private let phone: PhoneLink
    @ObservationIgnored private let hands: HandPipeline
    @ObservationIgnored private let listener = ConversationListener()
    @ObservationIgnored private var transcript = TranscriptBuilder()
    @ObservationIgnored private var frames: [LabRecording.Frame] = []
    @ObservationIgnored private var readings: [Reading] = []
    @ObservationIgnored private var started = Date()
    @ObservationIgnored private var ticker: Task<Void, Never>?
    /// The last notebook written, for saving.
    @ObservationIgnored private var last: (notebook: LabNotebook, recording: LabRecording, rehearsal: Bool, date: Date)?

    /// A frame every this many seconds.
    static let frameEvery = 4

    init(canvas: CanvasModel, probes: ProbeHub, phone: PhoneLink, hands: HandPipeline) {
        self.canvas = canvas
        self.probes = probes
        self.phone = phone
        self.hands = hands
    }

    /// Returns a line for the voice bar.
    func start() -> String {
        guard !isRecording else { return "Already taking lab notes" }
        transcript = TranscriptBuilder()
        frames = []
        readings = []
        started = Date()
        elapsed = 0
        isRecording = true
        listener.onText = { [weak self] text in
            guard let self else { return }
            transcript.heard(text, at: Date().timeIntervalSince(started))
        }
        let micProblem = listener.start()
        ticker = Task { [weak self] in
            var second = 0
            while !Task.isCancelled {
                self?.tick(second)
                second += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
        return micProblem.map { "Taking lab notes without sound: \($0)" } ?? "Taking lab notes: camera, speech and probes"
    }

    func stop() async -> String {
        guard isRecording else { return "Not taking lab notes" }
        ticker?.cancel()
        listener.stop()
        isRecording = false
        let recording = LabRecording(frames: frames, speech: transcript.lines(), readings: readings, duration: elapsed)
        return await write(recording, rehearsal: false)
    }

    func toggle() async -> String {
        isRecording ? await stop() : start()
    }

    /// Writes up the scripted rehearsal session, for practising without a bench.
    func rehearse() async -> String {
        await write(LabRehearsal.recording(), rehearsal: true)
    }

    /// Saves the last notebook to a folder on the Desktop: the notebook with its Methods, every
    /// reading as a CSV, the transcript and the frames.
    func save() -> String {
        guard let last else { return "Take some lab notes first" }
        let stamp = last.date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let folder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Grasp lab notebook \(stamp)")
        do {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("frames"), withIntermediateDirectories: true)
            let markdown = last.notebook.markdown(date: last.date, frames: last.recording.frames.count, rehearsal: last.rehearsal)
            try markdown.write(to: folder.appendingPathComponent("notebook.md"), atomically: true, encoding: .utf8)
            try LabNotebook.csv(last.recording.readings).write(to: folder.appendingPathComponent("readings.csv"), atomically: true, encoding: .utf8)
            let said = last.recording.speech.map { "\(clockTime($0.seconds))  \($0.text)" }.joined(separator: "\n")
            try said.write(to: folder.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
            for frame in last.recording.frames {
                let name = clockTime(frame.seconds).replacingOccurrences(of: ":", with: "m") + "s.jpg"
                try frame.jpeg.write(to: folder.appendingPathComponent("frames").appendingPathComponent(name))
            }
            NSWorkspace.shared.activateFileViewerSelecting([folder.appendingPathComponent("notebook.md")])
            return "Saved the lab notebook to your Desktop"
        } catch {
            return "Couldn't save the notebook: \(error.localizedDescription)"
        }
    }

    private func write(_ recording: LabRecording, rehearsal: Bool) async -> String {
        guard let client = GeminiClient.fromAppKeys else { return GeminiClient.Failure.missingKey.localizedDescription }
        guard recording.duration >= 5 else { return "That was too short to write up" }
        isWriting = true
        defer { isWriting = false }
        do {
            let notebook = try await LabNotebookWriter(client: client).write(recording)
            let date = Date()
            last = (notebook, recording, rehearsal, date)
            canvas.showNotebook(NotebookCard(notebook: notebook, frames: recording.frames, isRehearsal: rehearsal, date: date))
            return "Wrote the lab notebook: \(notebook.steps.count) steps"
        } catch {
            return "Couldn't write the notebook: \(error.localizedDescription)"
        }
    }

    /// Once a second: every probe's reading; every few seconds, a frame.
    private func tick(_ second: Int) {
        elapsed = Date().timeIntervalSince(started)
        for (cup, reading) in probes.latest where !probes.isStale(cup) {
            readings.append(Reading(cup: cup, celsius: reading.celsius, time: elapsed))
        }
        guard second % Self.frameEvery == 0 else { return }
        let at = elapsed
        // The phone sees the bench; without it, the Mac's camera.
        if case .connected = phone.state, let image = phone.liveImage, let jpeg = image.jpegData {
            frames.append(LabRecording.Frame(seconds: at, jpeg: jpeg))
        } else {
            hands.requestFrame { [weak self] data in
                guard let self, isRecording else { return }
                frames.append(LabRecording.Frame(seconds: at, jpeg: data))
            }
        }
    }
}

extension NSImage {
    /// About 640 points wide, as a JPEG.
    var jpegData: Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, 640 / Double(max(cgImage.width, 1)))
        let width = Int(Double(cgImage.width) * scale), height = Int(Double(cgImage.height) * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.6])
    }
}
