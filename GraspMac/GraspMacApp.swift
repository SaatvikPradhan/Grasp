import SwiftUI
import UniformTypeIdentifiers

@main
struct GraspMacApp: App {
    @State private var canvas: CanvasModel
    @State private var hands = HandPipeline()
    @State private var phone = PhoneLink()
    @State private var paper: PaperReader

    init() {
        let canvas = CanvasModel()
        _canvas = State(initialValue: canvas)
        _paper = State(initialValue: PaperReader(canvas: canvas))
    }

    var body: some Scene {
        Window("Grasp", id: "canvas") {
            CanvasView(model: canvas, pipeline: hands, phone: phone, paper: paper)
                .frame(minWidth: 960, minHeight: 640)
                .task {
                    phone.onCapture = { [paper] jpeg in paper.read(jpeg: jpeg) }
                    phone.start()
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
            CommandMenu("Canvas") {
                Button(canvas.showDebug ? "Hide Hand Debug" : "Show Hand Debug") { canvas.showDebug.toggle() }
                    .keyboardShortcut("d")
                Button("Reset Cards") { canvas.resetLayout() }
                    .keyboardShortcut("r")
                Divider()
                // Keyboard stand-ins for the twist, for rehearsing without a camera.
                Button("Shorter Term") { canvas.stepTerm(by: -1) }
                    .keyboardShortcut("[")
                Button("Longer Term") { canvas.stepTerm(by: 1) }
                    .keyboardShortcut("]")
            }
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
