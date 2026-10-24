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
                Text("Simulator: sending test frames")
                    .foregroundStyle(.white.opacity(0.7))
            }

            VStack {
                statusPill
                Spacer()
                controls
            }
            .padding(20)
        }
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

            Text(model.capturesSent == 0 ? "Send to Mac" : "Sent \(model.capturesSent)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
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
