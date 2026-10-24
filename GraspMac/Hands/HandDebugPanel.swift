import AVFoundation
import GraspKit
import SwiftUI

/// What the camera sees, the skeleton Vision found, and live gesture numbers for tuning.
/// Toggle with ⌘D.
struct HandDebugPanel: View {
    @Bindable var pipeline: HandPipeline
    let hands: [TrackedHand]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                CameraPreview(session: pipeline.capture.session)
                HandSkeleton(hands: hands, reach: pipeline.config.reach)
            }
            .aspectRatio(pipeline.aspect, contentMode: .fit)
            .frame(width: 320)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 12) {
                Text("\(Int(pipeline.fps.rounded())) fps")
                    .foregroundStyle(pipeline.fps >= 25 ? Theme.accent : Theme.hot)
                Text("\(hands.count) hand\(hands.count == 1 ? "" : "s")")
                Spacer()
                keyBadge("Gemini", isSet: APIKeys.gemini != nil)
                keyBadge("11Labs", isSet: APIKeys.elevenLabs != nil)
            }

            ForEach(hands) { hand in
                Text(describe(hand))
                    .foregroundStyle(hand.isPinching ? Theme.hot : Theme.muted)
            }

            slider("Pinch in", value: $pipeline.config.pinchEnter, in: 0.1...0.6)
            slider("Pinch out", value: $pipeline.config.pinchExit, in: 0.2...0.8)

            Text("⌘D hide · ⌘R reset · ⌘[ ⌘] term")
                .foregroundStyle(Theme.muted)
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(Theme.ink)
        .padding(12)
        .frame(width: 344)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
    }

    private func describe(_ hand: TrackedHand) -> String {
        let side = switch hand.chirality {
        case .left: "L"
        case .right: "R"
        case .unknown: "?"
        }
        var text = "#\(hand.id) \(side)  gap \(String(format: "%.2f", hand.pinchRatio))  \(hand.pinch)"
        if hand.pinch == .twist {
            text += String(format: " %+.0f°", hand.twist * 180 / .pi)
        }
        return text
    }

    private func keyBadge(_ name: String, isSet: Bool) -> some View {
        Text(name)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(isSet ? Theme.accent.opacity(0.25) : Theme.warn.opacity(0.25)))
            .help(isSet ? "\(name) key loaded" : "\(name) key missing: see Config/Secrets.example.xcconfig")
    }

    private func slider(_ label: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label).frame(width: 70, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue)).frame(width: 36, alignment: .trailing)
        }
    }
}

/// Bones and joints over the camera preview, plus the reach box that maps to the canvas.
private struct HandSkeleton: View {
    let hands: [TrackedHand]
    let reach: CGRect

    var body: some View {
        Canvas { context, size in
            func place(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }

            let box = CGRect(
                x: reach.minX * size.width, y: reach.minY * size.height,
                width: reach.width * size.width, height: reach.height * size.height
            )
            context.stroke(Path(roundedRect: box, cornerRadius: 6), with: .color(Theme.ink.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            for hand in hands {
                let color = hand.isPinching ? Theme.hot : Theme.accent
                for chain in HandJoint.chains {
                    var path = Path()
                    var started = false
                    for joint in chain {
                        guard let p = hand.joints[joint] else { started = false; continue }
                        if started { path.addLine(to: place(p)) } else { path.move(to: place(p)); started = true }
                    }
                    context.stroke(path, with: .color(color), lineWidth: 2)
                }
                for p in hand.joints.values {
                    let c = place(p)
                    context.fill(Path(ellipseIn: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5)), with: .color(Theme.ink))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The webcam feed, mirrored to match the hand points.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(session: session)
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {}

    final class PreviewView: NSView {
        private let preview = AVCaptureVideoPreviewLayer()

        init(session: AVCaptureSession) {
            super.init(frame: .zero)
            wantsLayer = true
            preview.session = session
            preview.videoGravity = .resizeAspectFill
            preview.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
            layer?.addSublayer(preview)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            preview.bounds = bounds
            preview.position = CGPoint(x: bounds.midX, y: bounds.midY)
            CATransaction.commit()
        }
    }
}
