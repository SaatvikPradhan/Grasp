import AVFoundation
import GraspKit
import SwiftUI

/// Full-screen camera with the link status on top and the send button below.
struct CameraView: View {
    @Bindable var model: PhoneModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.cameraStatus {
            case .starting:
                ProgressView().tint(.white)
            case .running:
                CameraPreview(camera: model.camera).ignoresSafeArea()
            case .denied:
                Text("Grasp needs the camera.\nTurn it on in Settings › Grasp.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
            case .testPattern:
                Text("Simulator: sending test frames.\nThe shutter sends the demo props in turn:\ncontract, window sticker, credit union quote.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let scan = model.scan {
                ScanResultView(scan: scan) { model.scan = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            VStack {
                statusPill
                Spacer()
                if model.scan == nil {
                    controls
                }
            }
            .padding(20)

            // A white flash on every capture, like a camera shutter.
            Color.white
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .phaseAnimator([0.0, 0.8, 0.0], trigger: model.flashCount) { flash, opacity in
                    flash.opacity(opacity)
                } animation: { opacity in
                    opacity > 0 ? .easeOut(duration: 0.06) : .easeIn(duration: 0.3)
                }
        }
        .animation(.spring(duration: 0.4), value: model.scan?.id)
        .task { await model.start() }
        .onAppear {
            // The phone often sits on a stand over the bench; don't let it sleep.
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(statusText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var statusText: String {
        switch model.linkState {
        case .searching:
            return "Looking for your Mac…"
        case .connecting(let peer):
            return "Connecting to \(peer)…"
        case .connected(let peer):
            guard let ms = model.roundTripMs else { return peer }
            return "\(peer) · \(Int(ms.rounded())) ms"
        }
    }

    private var statusColor: Color {
        switch model.linkState {
        case .searching: .gray
        case .connecting: .orange
        case .connected: .green
        }
    }

    private var controls: some View {
        HStack(alignment: .center) {
            Button {
                model.isLive.toggle()
            } label: {
                Label(model.isLive ? "Live" : "Paused", systemImage: model.isLive ? "video.fill" : "video.slash.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .tint(.white)

            Spacer()

            Button {
                model.capture()
            } label: {
                ZStack {
                    Circle().fill(.white).frame(width: 66, height: 66)
                    Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                }
            }
            .disabled(!model.isConnected)
            .opacity(model.isConnected ? 1 : 0.4)
            .accessibilityLabel("Send to Mac")

            Spacer()

            // Flick: hold the phone still on the paper, then flick its top away.
            Button {
                model.isFlickEnabled.toggle()
            } label: {
                Label(model.isFlickEnabled ? "Flick on" : "Flick off",
                      systemImage: model.isFlickEnabled ? "hand.wave.fill" : "hand.raised.slash.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .tint(.white)
        }
        .foregroundStyle(.white)
    }
}

private struct CameraPreview: UIViewRepresentable {
    let camera: PhoneCamera

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        camera.attach(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// The photo just sent, with the Mac's boxes over it: loan terms in green, add-ons in red.
private struct ScanResultView: View {
    let scan: PhoneScan
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 70)
            Image(uiImage: scan.image)
                .resizable()
                .scaledToFit()
                .overlay { boxes }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(radius: 20)

            Text(caption)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Button("Done", action: dismiss)
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            Spacer(minLength: 30)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.85))
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
    }

    /// Boxes drawn in the image's own space, so they line up however it's scaled.
    private var boxes: some View {
        GeometryReader { geometry in
            ForEach(Array((scan.highlights ?? []).enumerated()), id: \.offset) { _, box in
                let color: Color = box.kind == .term ? .green : .red
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.25))
                    .stroke(color, lineWidth: 2)
                    .frame(width: box.rect.width * geometry.size.width + 6, height: box.rect.height * geometry.size.height + 6)
                    .position(x: box.rect.midX * geometry.size.width, y: box.rect.midY * geometry.size.height)
            }
        }
    }

    private var caption: String {
        guard let highlights = scan.highlights else { return "Reading on your Mac…" }
        let terms = highlights.filter { $0.kind == .term }.count
        let addons = highlights.filter { $0.kind == .addon }.count
        switch (terms > 0, addons > 0) {
        case (true, true): return "Terms in green. Add-ons in red: ask to take them off."
        case (false, true): return "Add-ons in red: ask to take them off."
        case (true, false): return "Loan terms marked in green."
        case (false, false): return "Read on your Mac. Nothing to mark on this page."
        }
    }
}
