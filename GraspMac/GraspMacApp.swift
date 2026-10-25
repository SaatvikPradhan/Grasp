import GraspKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct GraspMacApp: App {
    @State private var canvas: CanvasModel
    @State private var hands: HandPipeline
    @State private var phone: PhoneLink
    @State private var paper: PaperReader
    @State private var probes: ProbeHub
    @State private var voice: VoiceController
    @State private var money: MoneyMode
    @State private var asker: Asker
    @State private var researcher: Researcher
    @State private var lab: LabSession

    init() {
        let canvas = CanvasModel()
        let money = MoneyMode(canvas: canvas)
        let asker = Asker(canvas: canvas, voiceOut: money.voiceOut)
        _canvas = State(initialValue: canvas)
        _paper = State(initialValue: PaperReader(canvas: canvas))
        _money = State(initialValue: money)
        let researcher = Researcher(canvas: canvas)
        let hands = HandPipeline(), phone = PhoneLink(), probes = ProbeHub()
        let lab = LabSession(canvas: canvas, probes: probes, phone: phone, hands: hands)
        _hands = State(initialValue: hands)
        _phone = State(initialValue: phone)
        _probes = State(initialValue: probes)
        _asker = State(initialValue: asker)
        _researcher = State(initialValue: researcher)
        _lab = State(initialValue: lab)
        _voice = State(initialValue: VoiceController(canvas: canvas, money: money, asker: asker, researcher: researcher, lab: lab))
    }

    var body: some Scene {
        Window("Grasp", id: "canvas") {
            CanvasView(model: canvas, pipeline: hands, phone: phone, paper: paper, probes: probes, voice: voice, money: money, asker: asker, lab: lab)
                .frame(minWidth: 960, minHeight: 640)
                .task {
                    phone.onCapture = { [paper] id, jpeg in paper.read(jpeg: jpeg, captureID: id) }
                    paper.onHighlights = { [phone] id, boxes in phone.sendHighlights(boxes, for: id) }
                    paper.onPage = { [researcher] document in researcher.pageRead(document) }
                    hands.onHands = { [voice] hands in voice.handsChanged(hands) }
                    money.isTakingCommand = { [voice] in voice.isBusy }
                    asker.onPointAt = { [phone] capture, box in phone.sendHighlights([box], for: capture) }
                    // Hovering a number on the Mac brings its page up on the phone, spot boxed.
                    canvas.onHoverChange = { [canvas, phone] target in
                        guard let target, let spot = canvas.phoneSpot(for: target) else { return }
                        phone.sendHighlights([spot.box], for: spot.captureID)
                    }
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
            CommandMenu("Ask") {
                Button("Ask Anything…") { asker.askByTyping() }
                    .keyboardShortcut("k")
            }
            CommandMenu("Research") {
                Button("Check My Notes Against the Paper…") { researcher.linkNotesByTyping() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button(lab.isRecording ? "Stop Lab Notes and Write Them Up" : "Start Lab Notes") { Task { await lab.toggle() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Compare My Cups with the Paper") { canvas.compareCupsWithPaper() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Button("Rehearse a Lab Session") { Task { await lab.rehearse() } }
                Button("Save Lab Notebook") { _ = lab.save() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandMenu("Bench") {
                // The simulated probes act out what hands would do at a real bench.
                ForEach(Cup.allCases) { cup in
                    Button("Pour Hot Water into Cup \(cup.rawValue)") { simulate(.pour(cup, celsius: 88), "poured into \(cup.rawValue)") }
                }
                Divider()
                ForEach(Cup.allCases) { cup in
                    Button("Put the Lid on Cup \(cup.rawValue)") { simulate(.lid(cup, on: true), "lid on \(cup.rawValue)") }
                }
                Divider()
                ForEach(Cup.allCases) { cup in
                    Button("Drop Ice into Cup \(cup.rawValue)") { simulate(.ice(cup), "ice into \(cup.rawValue)") }
                }
                Divider()
                Button("Show Cup Temperatures") { canvas.toggleTemperatures() }
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
                Button("Demo Cards") { canvas.resetLayout() }
                    .keyboardShortcut("r")
                Button("Delete Card in Focus") { canvas.deleteFocusedCard() }
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
        let view = CanvasView(model: canvas, pipeline: hands, phone: phone, paper: paper, probes: probes, voice: voice, money: money, asker: asker, lab: lab, isSnapshot: true)
        return CanvasSnapshot.save(view, size: canvas.canvasSize, to: url)
    }

    /// `GRASP_SNAPSHOT=/path/shot.png` saves one snapshot after launch, so the canvas can be
    /// checked without screen recording permission. `GRASP_SNAPSHOT_DELAY=seconds` waits longer;
    /// `GRASP_SNAPSHOT_SETUP=demo,quote,compare,term48,lines,advice,summary,read:/path.jpg,hover,hovertotal` runs the
    /// matching commands first.
    private func scheduleSnapshotFromEnvironment() {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["GRASP_SNAPSHOT"] else { return }
        let delay = environment["GRASP_SNAPSHOT_DELAY"].flatMap(Double.init) ?? 6
        let setup = environment["GRASP_SNAPSHOT_SETUP"]?.split(separator: ",").map(String.init) ?? []
        Task {
            try? await Task.sleep(for: .seconds(delay))
            for step in setup {
                switch step {
                case "demo": canvas.resetLayout()
                case "quote": canvas.addDemoQuote()
                case "compare": canvas.compareLoans()
                case "term48": canvas.setTerm(48)
                case "lines": canvas.toggleFrontStyle()
                case "advice": await money.whatToSay()
                case let step where step.hasPrefix("read:"):
                    paper.read(fileAt: URL(filePath: String(step.dropFirst(5))))
                    try? await Task.sleep(for: .seconds(9))
                case let step where step.hasPrefix("ask:"):
                    await asker.ask(String(step.dropFirst(4)))
                case let step where step.hasPrefix("hovernote"):
                    // hovernote2: the passage behind the second note.
                    let index = (Int(step.dropFirst(9)) ?? 1) - 1
                    if let card = canvas.cards.last(where: { if case .notes = $0.kind { true } else { false } }) {
                        canvas.showSource(of: .passage(card: card.id, index: index))
                    }
                case "lab": await lab.rehearse()
                case "temps": if !canvas.showsTemperatures { canvas.toggleTemperatures() }
                case "comparecups": canvas.compareCupsWithPaper()
                case let step where step.hasPrefix("pour:"):
                    // pour:A, lid:B, ice:C act on the simulated bench.
                    let cup = Cup(rawValue: String(step.dropFirst(5))) ?? .a
                    simulate(.pour(cup, celsius: 88), "poured into \(cup.rawValue)")
                case let step where step.hasPrefix("lid:"):
                    let cup = Cup(rawValue: String(step.dropFirst(4))) ?? .b
                    simulate(.lid(cup, on: true), "lid on \(cup.rawValue)")
                case let step where step.hasPrefix("ice:"):
                    let cup = Cup(rawValue: String(step.dropFirst(4))) ?? .c
                    simulate(.ice(cup), "ice into \(cup.rawValue)")
                case let step where step.hasPrefix("wait"):
                    // wait30: let the bench run half a minute.
                    try? await Task.sleep(for: .seconds(Double(step.dropFirst(4)) ?? 10))
                case let step where step.hasPrefix("hovercited"):
                    // hovercited7: the seventh thing the newest research card cites, from 1.
                    let index = (Int(step.dropFirst(10)) ?? 1) - 1
                    if let card = canvas.cards.last(where: { !canvas.citations(for: $0).isEmpty }) {
                        canvas.showSource(of: .cited(card: card.id, index: index))
                    }
                case let step where step.hasPrefix("hoverstep"):
                    // hoverstep4: the fourth step of the lab notebook.
                    let index = (Int(step.dropFirst(9)) ?? 1) - 1
                    if let card = canvas.cards.last(where: { if case .notebook = $0.kind { true } else { false } }) {
                        canvas.showSource(of: .labStep(card: card.id, index: index))
                    }
                case "hoveranswer":
                    if let card = canvas.cards.last(where: { if case .answer = $0.kind { true } else { false } }) {
                        canvas.showSource(of: .answerSource(card: card.id, index: 0))
                    }
                case "hover":
                    // The first located fact on the newest document card.
                    if let document = canvas.cards.reversed().compactMap({ canvas.document(for: $0) }).first,
                       let fact = document.shownFacts.first(where: { document.factBoxes[$0.key] != nil }) {
                        canvas.showSource(of: .fact(document: document.id, key: fact.key))
                    }
                case "hovertotal":
                    if let card = canvas.cards.last(where: { canvas.document(for: $0) != nil }) {
                        canvas.showSource(of: .derived(card: card.id, name: "total"))
                    }
                case "summary": await money.saveSummary(to: URL(filePath: path + "-summary.pdf"), open: false)
                default: break
                }
                try? await Task.sleep(for: .seconds(1))
            }
            _ = saveSnapshot(to: URL(filePath: path))
        }
    }

    /// Acts on the simulated bench and marks it on the live chart. Real probes need real hands.
    private func simulate(_ action: SimulatedBench.Action, _ label: String) {
        guard probes.simulate(action) else { return }
        probes.mark(label)
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
