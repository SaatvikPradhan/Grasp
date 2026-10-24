import GraspKit
import SwiftUI

/// What the iPhone sees, top right of the canvas. Gate G2 passes when a frame shows up
/// here within 300 ms.
struct PhonePanel: View {
    let phone: PhoneLink

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if let ms = phone.oneWayMs {
                    Text("\(Int(ms.rounded())) ms")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(ms <= 300 ? Theme.accent : Theme.warn)
                        .help("About how long a frame takes to arrive (half the round trip). G2 wants under 300 ms.")
                }
            }

            if isConnected, let image = phone.liveImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("\(Int(phone.framesPerSecond.rounded())) fps live")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            } else if !isConnected {
                Text("Open Grasp on your iPhone. Wi-Fi and Bluetooth must be on, but they don't need to share a network.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let capture = phone.lastCapture {
                Text("CAPTURE \(phone.captureCount)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Image(nsImage: capture)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(12)
        .frame(width: 280)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
    }

    private var isConnected: Bool {
        if case .connected = phone.state { return true }
        return false
    }

    private var title: String {
        switch phone.state {
        case .searching: "Waiting for iPhone"
        case .connecting(let peer): "Connecting to \(peer)…"
        case .connected(let peer): peer
        }
    }

    private var statusColor: Color {
        switch phone.state {
        case .searching: Theme.muted
        case .connecting: Theme.hot
        case .connected: Theme.accent
        }
    }
}
