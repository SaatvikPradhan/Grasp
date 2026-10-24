import SwiftUI

@main
struct GraspMacApp: App {
    @State private var canvas = CanvasModel()
    @State private var hands = HandPipeline()

    var body: some Scene {
        Window("Grasp", id: "canvas") {
            CanvasView(model: canvas, pipeline: hands)
                .frame(minWidth: 960, minHeight: 640)
                .task { await hands.start(feeding: canvas) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
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
}
