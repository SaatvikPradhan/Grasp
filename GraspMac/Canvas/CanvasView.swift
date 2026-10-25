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
    let asker: Asker
    let lab: LabSession
    let guide: ProtocolGuide
    /// Rendering to a PNG: leaves out the camera preview and drop target, which can't be drawn offscreen.
    /// Where sessions are kept, for its status under the title; nil in snapshots.
    var tiger: TigerStore?
    /// Reads videos dropped on the canvas.
    var videos: VideoStudy?
    var isSnapshot = false
    @State private var popoverSize = CGSize(width: 400, height: 300)

    var body: some View {
        ZStack(alignment: .topLeading) {
            GridBackground()

            if model.cards.isEmpty {
                EmptyCanvasHint()
            }

            ForEach(model.chipTrays) { tray in
                ChipTrayView(tray: tray)
                    .position(x: tray.frame.midX, y: tray.frame.midY)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            ForEach(model.cards) { card in
                CardView(
                    card: card,
                    isHeld: model.isHeld(card.id),
                    isMergeCandidate: model.mergeCandidates.contains(card.id),
                    isTrashTarget: model.trashTarget == card.id,
                    isFocused: model.focusedID == card.id && model.cards.count > 1,
                    probes: probes,
                    guide: guide
                )
                    .position(card.center)
                    .animation(
                        card.isArriving ? .spring(duration: 0.8, bounce: 0.3) : .interactiveSpring(response: 0.28, dampingFraction: 0.82),
                        value: card.center
                    )
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    // Mouse stand-ins: drag to move (and onto another loan to compare),
                    // click to focus (and open a chip), double-click to switch bars and lines.
                    .onTapGesture(count: 2) { model.toggleStyle(of: card.id) }
                    .onTapGesture { model.focus(card.id) }
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
                    PhonePanel(phone: phone, showsHelp: model.cards.isEmpty)
                    PaperPanel(reader: paper)
                }
                .onGeometryChange(for: Double.self) { $0.size.height } action: { model.panelHeight = $0 + 36 }
            }
            .padding(.top, 36)
            .padding(.trailing, 20)

            VStack {
                Spacer()
                VoiceBar(voice: voice, money: money, asker: asker, lab: lab)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)

            TrashBin(isHot: model.trashTarget != nil)
                .position(model.trashCenter)
                .opacity(model.isTrashVisible ? 1 : 0)
                .scaleEffect(model.isTrashVisible ? 1 : 0.6)
                .animation(.spring(duration: 0.3), value: model.isTrashVisible)
                .allowsHitTesting(false)

            if let hovered = model.hovered, let frame = model.hoverFrame(hovered),
               let provenance = model.provenance(for: hovered) {
                ProvenancePopover(provenance: provenance)
                    .onGeometryChange(for: CGSize.self) { proxy in proxy.size } action: { popoverSize = $0 }
                    .position(popoverPosition(beside: frame))
                    .transition(.opacity)
            }

            // Cursors last so they draw over everything; they never take clicks.
            ForEach(model.hands) { hand in
                HandCursor(mode: model.cursorState(for: hand))
                    .position(model.point(for: hand))
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(.named(CanvasModel.space))
        .environment(model)
        .environment(\.isCanvasSnapshot, isSnapshot)
        .animation(.easeOut(duration: 0.15), value: model.hovered)
        .modifier(PhotoDropTarget(paper: paper, videos: videos, isEnabled: !isSnapshot))
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            model.setCanvasSize(size)
        }
        .background(Theme.paper)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    /// To the right of the hovered item if there's room, otherwise to its left; kept on screen.
    private func popoverPosition(beside frame: CGRect) -> CGPoint {
        let width = popoverSize.width, height = popoverSize.height
        let size = model.canvasSize
        let right = frame.maxX + 16 + width / 2
        let x = right <= size.width ? right : frame.minX - 16 - width / 2
        let y = min(max(frame.midY, height / 2 + 10), size.height - height / 2 - 10)
        return CGPoint(x: min(max(x, width / 2 + 10), size.width - width / 2 - 10), y: y)
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
            if let tiger, let line = storageLine(tiger.status) {
                Label(line.text, systemImage: "cylinder.split.1x2")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(line.isProblem ? Theme.warn : Theme.muted)
                    .lineLimit(1)
            }
        }
        .allowsHitTesting(false)
    }

    private func storageLine(_ status: TigerStore.Status) -> (text: String, isProblem: Bool)? {
        switch status {
        case .off: nil
        case .connecting: ("Connecting to Tiger Data…", false)
        case .saving(let rows): ("Tiger Data · \(rows) row\(rows == 1 ? "" : "s") saved", false)
        case .failed(let message): ("Tiger Data: \(message)", true)
        }
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

/// What an empty canvas says: hand it anything.
private struct EmptyCanvasHint: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Theme.muted)
            Text("Hand Grasp anything with numbers on it")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("A lease, a phone bill, a loan, a credit card offer, a paper.\nHold it up to the phone and tap, or drop a photo here.")
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
            Text("Then hover any number to see where it came from, or make a fist and ask anything.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// Drop a photo of a contract on the canvas to read it without the phone.
private struct PhotoDropTarget: ViewModifier {
    let paper: PaperReader
    let videos: VideoStudy?
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                if let videos {
                    GraspMacApp.read(url, paper: paper, videos: videos)
                } else {
                    paper.read(fileAt: url)
                }
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
