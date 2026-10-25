import SwiftUI
import UniformTypeIdentifiers

@main
struct GraspMacApp: App {
    @State private var canvas: CanvasModel
    @State private var hands = HandPipeline()
    @State private var phone = PhoneLink()
    @State private var paper: PaperReader
    @State private var probes = ProbeHub()
    @State private var voice: VoiceController
    @State private var money: MoneyMode

    init() {
        let canvas = CanvasModel()
        let money = MoneyMode(canvas: canvas)
        _canvas = State(initialValue: canvas)
        _paper = State(initialValue: PaperReader(canvas: canvas))
        _money = State(initialValue: money)
        _voice = State(initialValue: VoiceController(canvas: canvas, money: money))
    }

    var body: some Scene {
        Window("Grasp", id: "canvas") {
            CanvasView(model: canvas, pipeline: hands, phone: phone, paper: paper, probes: probes, voice: voice, money: money)
                .frame(minWidth: 960, minHeight: 640)
                .task {
                    phone.onCapture = { [paper] id, jpeg in paper.read(jpeg: jpeg, captureID: id) }
                    paper.onHighlights = { [phone] id, boxes in phone.sendHighlights(boxes, for: id) }
                    hands.onHands = { [voice] hands in voice.handsChanged(hands) }
                    money.isTakingCommand = { [voice] in voice.isBusy }
                    phone.start()
                    probes.start()
                    Task { await voice.start() }
                    scheduleSnapshotFromEnvironment()
                    await hands.start(feeding: canvas)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Read Image…") { openImage() }
                    .keyboardShortcut("o")
            }
            CommandMenu("Money") {
                Button("What to Say") { Task { await money.whatToSay() } }
                    .keyboardShortcut("j")
                Button(money.conversation.isOn ? "Stop Listening to the Salesperson" : "Listen to the Salesperson…") {
                    money.listenToPitch(!money.conversation.isOn)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Save Decision Summary") { Task { await money.saveSummary() } }
                    .keyboardShortcut("e")
            }
            CommandMenu("Canvas") {
                Button(canvas.showDebug ? "Hide Hand Debug" : "Show Hand Debug") { canvas.showDebug.toggle() }
                    .keyboardShortcut("d")
                Button(canvas.showsTemperatures ? "Hide Cup Temperatures" : "Show Cup Temperatures") { canvas.toggleTemperatures() }
                    .keyboardShortcut("t")
                Button("Reset Cards") { canvas.resetLayout() }
                    .keyboardShortcut("r")
                Button("Delete Front Card") { canvas.deleteFrontCard() }
                    .keyboardShortcut(.delete, modifiers: [])
                Button("Clear Canvas") { canvas.clearCanvas() }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
                Button("Save Snapshot to Desktop") { _ = saveSnapshot(to: CanvasSnapshot.desktopURL) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                // Keyboard stand-ins for the gestures, for rehearsing without a camera.
                Button("Shorter Term") { canvas.stepDial(by: -1) }
                    .keyboardShortcut("[")
                Button("Longer Term") { canvas.stepDial(by: 1) }
                    .keyboardShortcut("]")
                Button("Switch Bars and Lines") { canvas.toggleFrontStyle() }
                    .keyboardShortcut("l")
                Button("Compare Loans") { canvas.compareLoans() }
                    .keyboardShortcut("m")
                Button("Add Demo Credit Union Quote") { canvas.addDemoQuote() }
                    .keyboardShortcut("u")
            }
        }
    }

    private func saveSnapshot(to url: URL) -> Bool {
        let view = CanvasView(model: canvas, pipeline: hands, phone: phone, paper: paper, probes: probes, voice: voice, money: money, isSnapshot: true)
        return CanvasSnapshot.save(view, size: canvas.canvasSize, to: url)
    }

    /// `GRASP_SNAPSHOT=/path/shot.png` saves one snapshot after launch, so the canvas can be
    /// checked without screen recording permission. `GRASP_SNAPSHOT_DELAY=seconds` waits longer;
    /// `GRASP_SNAPSHOT_SETUP=quote,compare,term48,lines,advice,summary` runs the matching menu commands first.
    private func scheduleSnapshotFromEnvironment() {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["GRASP_SNAPSHOT"] else { return }
        let delay = environment["GRASP_SNAPSHOT_DELAY"].flatMap(Double.init) ?? 6
        let setup = environment["GRASP_SNAPSHOT_SETUP"]?.split(separator: ",").map(String.init) ?? []
        Task {
            try? await Task.sleep(for: .seconds(delay))
            for step in setup {
                switch step {
                case "quote": canvas.addDemoQuote()
                case "compare": canvas.compareLoans()
                case "term48": canvas.setTerm(48)
                case "lines": canvas.toggleFrontStyle()
                case "advice": await money.whatToSay()
                case "summary": await money.saveSummary(to: URL(filePath: path + "-summary.pdf"), open: false)
                default: break
                }
                try? await Task.sleep(for: .seconds(1))
            }
            _ = saveSnapshot(to: URL(filePath: path))
        }
    }

    /// Reads a photo from disk as if the phone had sent it.
    private func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a photo of a contract, window sticker or loan quote"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        paper.read(fileAt: url)
    }
}
