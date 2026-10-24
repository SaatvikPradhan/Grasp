import GraspKit
import SwiftUI

struct CanvasView: View {
    @Bindable var model: CanvasModel
    @Bindable var pipeline: HandPipeline

    var body: some View {
        ZStack(alignment: .topLeading) {
            GridBackground()

            ForEach(model.cards) { card in
                ChartCardView(card: card, isHeld: model.isHeld(card.id))
                    .frame(width: card.size.width, height: card.size.height)
                    .position(card.center)
                    .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.82), value: card.center)
                    .gesture(
                        DragGesture()
                            .onChanged { model.mouseDrag(card.id, translation: $0.translation) }
                            .onEnded { _ in model.endMouseDrag() }
                    )
            }

            header
                .padding(.top, 36)
                .padding(.leading, 28)

            if model.showDebug {
                VStack {
                    Spacer()
                    HandDebugPanel(pipeline: pipeline, hands: model.hands)
                }
                .padding(20)
            }

            // Cursors last so they draw over everything; they never take clicks.
            ForEach(model.hands) { hand in
                HandCursor(mode: model.cursorState(for: hand))
                    .position(model.point(for: hand))
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            model.setCanvasSize(size)
        }
        .background(Theme.paper)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GRASP")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .tracking(3)
                .foregroundStyle(Theme.ink)
            Text(statusLine)
                .font(.system(size: 14))
                .foregroundStyle(pipeline.status == .running ? Theme.muted : Theme.warn)
        }
        .allowsHitTesting(false)
    }

    private var statusLine: String {
        switch pipeline.status {
        case .starting:
            return "Starting the camera…"
        case .cameraDenied:
            return "Camera access is off. Turn it on in System Settings › Privacy & Security › Camera, then reopen Grasp."
        case .noCamera:
            return "No camera found."
        case .failed(let message):
            return "Camera failed: \(message)"
        case .running:
            if model.hands.isEmpty { return "Raise a hand in front of the camera." }
            if model.hands.contains(where: \.isPinching) { return "Move to drag. Turn your wrist to dial." }
            return "Pinch a chart to grab it."
        }
    }
}

private struct GridBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 28
            var path = Path()
            for x in stride(from: 0, through: size.width, by: spacing) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: spacing) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(Theme.grid), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}
