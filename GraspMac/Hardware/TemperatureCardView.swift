import Charts
import GraspKit
import SwiftUI

/// Live cup temperatures. Lines show the last two minutes; bars show each cup now.
/// ⌘T adds or removes the card.
struct TemperatureCardView: View {
    let hub: ProbeHub
    let style: Card.Style

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CUP TEMPERATURES")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.muted)

            HStack(spacing: 22) {
                ForEach(Cup.allCases) { cup in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cup \(cup.rawValue)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(color(cup))
                        Text(value(cup))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(hub.isStale(cup) ? Theme.muted : Theme.ink)
                            .contentTransition(.numericText())
                    }
                }
            }

            Group {
                switch style {
                case .primary: lines
                case .alternate: bars
                }
            }
            .frame(maxHeight: .infinity)
            .clipped()

            Text(footer)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
        }
        .animation(.easeOut(duration: 0.3), value: hub.latest[.a]?.time)
    }

    private var footer: String {
        if hub.isSimulated { return "Simulated probes · plug in the board for real readings" }
        let room = hub.room.map { " · room " + String(format: "%.1f", $0) + " °C" } ?? ""
        return "Live · \(hub.sourceName)" + room
    }

    private var lines: some View {
        let now = hub.now
        return Chart {
            ForEach(Cup.allCases) { cup in
                ForEach((hub.history[cup] ?? []).filter { now - $0.time <= ProbeHub.window }, id: \.time) { reading in
                    LineMark(
                        x: .value("Seconds ago", reading.time - now),
                        y: .value("°C", reading.celsius),
                        series: .value("Cup", cup.rawValue)
                    )
                    .foregroundStyle(color(cup))
                    .interpolationMethod(.monotone)
                }
            }
            ForEach(hub.markers.filter { now - $0.time <= ProbeHub.window }) { marker in
                RuleMark(x: .value("Seconds ago", marker.time - now))
                    .foregroundStyle(Theme.hot.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(marker.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.hot)
                            .lineLimit(1)
                    }
            }
        }
        .chartXScale(domain: -ProbeHub.window...0)
        .chartXAxis {
            AxisMarks(values: [-120, -90, -60, -30, 0]) { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(seconds == 0 ? "now" : "\(Int(seconds)) s")
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel {
                    if let celsius = value.as(Double.self) {
                        Text("\(Int(celsius))°")
                    }
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }

    private var bars: some View {
        Chart {
            ForEach(Cup.allCases) { cup in
                if let reading = hub.latest[cup] {
                    BarMark(x: .value("Cup", "Cup \(cup.rawValue)"), y: .value("°C", reading.celsius))
                        .foregroundStyle(color(cup))
                        .annotation(position: .top) {
                            Text(String(format: "%.1f°", reading.celsius))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.ink)
                        }
                }
            }
        }
        .chartYAxis(.hidden)
    }

    private func value(_ cup: Cup) -> String {
        guard let reading = hub.latest[cup] else { return "—" }
        return String(format: "%.1f °C", reading.celsius)
    }

    private func color(_ cup: Cup) -> Color {
        switch cup {
        case .a: Theme.warn
        case .b: Theme.accent
        case .c: Theme.cool
        }
    }
}
