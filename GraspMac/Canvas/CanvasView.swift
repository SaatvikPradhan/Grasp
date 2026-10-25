import GraspKit
import SwiftUI

struct CanvasView: View {
    @Bindable var model: CanvasModel
    @Bindable var pipeline: HandPipeline
    let phone: PhoneLink
    let paper: PaperReader
    let probes: ProbeHub
    let voice: VoiceController
    let money: MoneyMode
    /// Rendering to a PNG: leaves out the camera preview and drop target, which can't be drawn offscreen.
    var isSnapshot = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            GridBackground()

            ForEach(model.cards) { card in
                CardView(
                    card: card,
                    isHeld: model.isHeld(card.id),
                    isMergeCandidate: model.mergeCandidates.contains(card.id),
                    isTrashTarget: model.trashTarget == card.id,
                    probes: probes
                )
                    .position(card.center)
                    .animation(
                        card.isArriving ? .spring(duration: 0.8, bounce: 0.3) : .interactiveSpring(response: 0.28, dampingFraction: 0.82),
                        value: card.center
                    )
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    // Mouse stand-ins: drag to move (and onto another loan to compare),
                    // double-click to switch bars and lines.
                    .onTapGesture(count: 2) { model.toggleStyle(of: card.id) }
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { model.mouseDrag(card.id, translation: $0.translation) }
                            .onEnded { _ in model.endMouseDrag() }
                    )
            }

            header
                .padding(.top, 36)
                .padding(.leading, 28)

            if model.showDebug && !isSnapshot {
                VStack {
                    Spacer()
                    HandDebugPanel(pipeline: pipeline, hands: model.hands)
                }
                .padding(20)
            }

            HStack(alignment: .top) {
                Spacer()
                VStack(spacing: 12) {
                    PhonePanel(phone: phone)
                    PaperPanel(reader: paper)
                }
            }
            .padding(.top, 36)
            .padding(.trailing, 20)

            VStack {
                Spacer()
                VoiceBar(voice: voice, money: money)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)

            TrashBin(isHot: model.trashTarget != nil)
                .position(model.trashCenter)
                .opacity(model.isTrashVisible ? 1 : 0)
                .scaleEffect(model.isTrashVisible ? 1 : 0.6)
                .animation(.spring(duration: 0.3), value: model.isTrashVisible)
                .allowsHitTesting(false)

            // Cursors last so they draw over everything; they never take clicks.
            ForEach(model.hands) { hand in
                HandCursor(mode: model.cursorState(for: hand))
                    .position(model.point(for: hand))
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(PhotoDropTarget(paper: paper, isEnabled: !isSnapshot))
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
            if model.hands.contains(where: \.isPinching) { return "Move to drag. Turn your wrist to dial. Push two loans together to compare." }
            if model.hands.contains(where: \.isFist) { return "Listening. Open your hand to send." }
            if model.hands.contains(where: \.isOpenPalm) { return "Swipe an open hand across a chart to switch bars and lines." }
            return "Pinch a chart to grab it. Make a fist to talk."
        }
    }
}

/// Drop a photo of a contract on the canvas to read it without the phone.
private struct PhotoDropTarget: ViewModifier {
    let paper: PaperReader
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                paper.read(fileAt: url)
                return true
            }
        } else {
            content
        }
    }
}

private struct GridBackground: View {
    var body: some View {
        GridLines(spacing: 28)
            .stroke(Theme.grid, lineWidth: 1)
            .allowsHitTesting(false)
    }
}

/// A plain shape rather than a Canvas, so canvas snapshots render it too.
private struct GridLines: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for x in stride(from: rect.minX, through: rect.maxX, by: spacing) {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for y in stride(from: rect.minY, through: rect.maxY, by: spacing) {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}
