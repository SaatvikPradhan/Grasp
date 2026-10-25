import SwiftUI

/// The on-screen hand, in the four states from GRASP.md section 4.
struct HandCursor: View {
    enum Mode: Equatable {
        /// Gray ring that follows the hand.
        case open
        /// Green ring: a pinch here would grab a chart.
        case overCard
        /// Orange ring with thumb and index dots.
        case pinch
        /// Orange arc filled to the dialed value.
        case twist(fraction: Double, label: String)
        /// A fist: Grasp is listening.
        case talking
    }

    let mode: Mode

    var body: some View {
        ZStack {
            switch mode {
            case .open:
                Circle()
                    .stroke(Theme.muted.opacity(0.85), lineWidth: 3)
                    .frame(width: 44, height: 44)
            case .overCard:
                Circle()
                    .fill(Theme.accent.opacity(0.18))
                    .overlay(Circle().stroke(Theme.accent, lineWidth: 4))
                    .frame(width: 54, height: 54)
            case .pinch:
                Circle()
                    .stroke(Theme.hot, lineWidth: 4)
                    .frame(width: 34, height: 34)
                HStack(spacing: 3) {
                    Circle().fill(Theme.hot).frame(width: 8, height: 8)
                    Circle().fill(Theme.hot).frame(width: 8, height: 8)
                }
            case .talking:
                Circle()
                    .fill(Theme.warn.opacity(0.2))
                    .overlay(Circle().stroke(Theme.warn, lineWidth: 4))
                    .frame(width: 58, height: 58)
                Image(systemName: "mic.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.warn)
                    .symbolEffect(.pulse, options: .repeating)
            case .twist(let fraction, let label):
                Circle()
                    .stroke(Theme.hot.opacity(0.25), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: max(fraction, 0.02))
                    .stroke(Theme.hot, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(label)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
        }
        .frame(width: 76, height: 76)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        .animation(.spring(duration: 0.18), value: mode)
    }
}

#Preview {
    HStack(spacing: 24) {
        HandCursor(mode: .open)
        HandCursor(mode: .overCard)
        HandCursor(mode: .pinch)
        HandCursor(mode: .twist(fraction: 0.4, label: "48 mo"))
        HandCursor(mode: .talking)
    }
    .padding(40)
    .background(Theme.paper)
}
