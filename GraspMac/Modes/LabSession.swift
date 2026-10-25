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
    /// The last few words heard, shown while recording so you can see it's listening.
    private(set) var lastHeard = ""
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

    /// A command said at the bench ("done", "go back", "stop recording"), with the words heard:
    /// hands are wet or full, so no fist or Space is needed while recording.
    @ObservationIgnored var onCommand: ((BenchCommand, String) -> Void)?
    /// True while words shouldn't count as commands: Grasp talking, or a fist or Space command underway.
    @ObservationIgnored var ignoresCommands: () -> Bool = { false }
    /// The recognizer's text, waiting for a pause before it's checked for a command.
    @ObservationIgnored private var unchecked: String?
    /// This recognizer session's text at the last check.
    @ObservationIgnored private var checked = ""
    /// Words heard in earlier recognizer sessions, and in this one, for a fist or Space while recording.
    @ObservationIgnored private var earlierWords: [Substring] = []
    @ObservationIgnored private var sessionWords: [Substring] = []
    @ObservationIgnored private var ignoredSome = false
    @ObservationIgnored private var pause: Task<Void, Never>?

    /// A phrase is finished once nothing new is heard for this long.
    static let commandPause = Duration.milliseconds(800)

    /// A frame every this many seconds.
    static let frameEvery = 4

    /// The newest bench frame while recording, for the guided run to look at.
    var latestFrame: LabRecording.Frame? { isRecording ? frames.last : nil }

    /// What people say at the bench, so "cup A" isn't heard as "cupcake".
    static let benchWords = ["cup A", "cup B", "cup C", "lid", "lid on", "lid off", "ice", "ice cubes", "pour", "pouring",
                             "probe", "degrees", "Celsius", "stir", "timer", "Grasp", "done", "next step"]

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
        lastHeard = ""
        listener.contextualStrings = Self.benchWords
        checked = ""
        unchecked = nil
        earlierWords = []
        sessionWords = []
        listener.onNewSession = { [weak self] in
            guard let self else { return }
            transcript.endSession()
            // The text starts over: check what was still waiting first.
            checkForCommand()
            checked = ""
            earlierWords += sessionWords
            sessionWords = []
        }
        listener.onText = { [weak self] text in
            guard let self else { return }
            transcript.heard(text, at: Date().timeIntervalSince(started))
            sessionWords = text.split(separator: " ")
            lastHeard = sessionWords.suffix(8).joined(separator: " ")
            waitForPause(after: text)
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

    /// Stops and writes the notebook, with the protocol as it was followed when the run was guided.
    func stop(protocol record: ProtocolRecord? = nil) async -> String {
        guard isRecording else { return "Not taking lab notes" }
        ticker?.cancel()
        pause?.cancel()
        listener.stop()
        isRecording = false
        let recording = LabRecording(frames: frames, speech: transcript.lines(), readings: readings, duration: elapsed,
                                     protocolRecord: record)
        // Snapshot runs keep what was heard, to check the listener.
        if let path = ProcessInfo.processInfo.environment["GRASP_SNAPSHOT"] {
            try? recording.speech.map { "\(clockTime($0.seconds))  \($0.text)" }.joined(separator: "\n")
                .write(toFile: path + "-transcript.txt", atomically: true, encoding: .utf8)
        }
        return await write(recording, rehearsal: false)
    }

    func toggle() async -> String {
        isRecording ? await stop() : start()
    }

    /// Writes up the scripted rehearsal session, for practising without a bench.
    func rehearse() async -> String {
        await write(LabRehearsal.recording(), rehearsal: true)
    }

    /// Saves the last notebook to a folder on the Desktop (or in `parent`): the notebook with its
    /// Methods, every reading as a CSV, the transcript, the frames, and a time-lapse of the run.
    func save(in parent: URL? = nil) async -> String {
        guard let last else { return "Take some lab notes first" }
        let stamp = last.date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let folder = (parent ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0])
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
            // The run in under a minute: each frame a quarter of a second, captioned with the step and the cups.
            var video = ""
            if !last.recording.frames.isEmpty {
                let notebook = last.notebook, readings = last.recording.readings
                do {
                    try await TimeLapse.write(last.recording.frames,
                                              captions: { TimeLapseCaption.caption(at: $0, notebook: notebook, readings: readings) },
                                              to: folder.appendingPathComponent("timelapse.mp4"))
                    video = ", with a time-lapse of the run"
                } catch {
                    video = " (no time-lapse: \(error.localizedDescription))"
                }
            }
            if parent == nil { NSWorkspace.shared.activateFileViewerSelecting([folder.appendingPathComponent("notebook.md")]) }
            return "Saved the lab notebook to your Desktop" + video
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

    // MARK: Commands

    /// How many words have been heard so far: a fist or Space while recording takes the words
    /// after it from this listener, as a second recognizer on the mic would cut this one off.
    func wordsHeard() -> Int { earlierWords.count + sessionWords.count }

    func words(since count: Int) -> String {
        (earlierWords + sessionWords).dropFirst(count).joined(separator: " ")
    }

    private func waitForPause(after text: String) {
        unchecked = text
        if ignoresCommands() { ignoredSome = true }
        pause?.cancel()
        pause = Task { [weak self] in
            try? await Task.sleep(for: Self.commandPause)
            guard !Task.isCancelled else { return }
            self?.checkForCommand()
        }
    }

    /// The words since the last pause, as one phrase: a command if it ends with one.
    private func checkForCommand() {
        guard let text = unchecked else { return }
        unchecked = nil
        let said = BenchCommand.newWords(text, since: checked)
        checked = text
        // Grasp reading a step aloud, heard back through the mic, isn't a command.
        let ignored = ignoredSome || ignoresCommands()
        ignoredSome = false
        guard isRecording, !ignored, let said, let command = BenchCommand.ending(said) else { return }
        onCommand?(command, said)
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
