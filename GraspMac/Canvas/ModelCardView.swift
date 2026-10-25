import Charts
import GraspKit
import SwiftUI

/// Numbers in a paper model, printed the way the paper prints them: 0.031, 18.4, 33.6.
enum PaperModelText {
    static func number(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        if abs(value) < 1 { return String(format: "%.3f", value) }
        return String(format: "%.1f", value)
    }
}

/// A paper's model, running: every condition's curve, the paper's reported results on it (red
/// where the paper's own equation disagrees), twist for k, swipe for the next condition. Pushed
/// into the cup chart, it shows each cup on the bench against what the paper predicts for it.
struct ModelCardView: View {
    let cardID: UUID
    let card: ModelCard
    let probes: ProbeHub
    @Environment(CanvasModel.self) private var canvas

    private var model: PaperModel { card.model }
    /// Seconds in one of the paper's time units.
    private var unitSeconds: Double { ["s": 1, "h": 3_600][model.timeUnit] ?? 60 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LIVE MODEL · " + (model.kind == .newtonCooling ? "NEWTON'S LAW OF COOLING" : "EXPONENTIAL DECAY"))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text(card.paperTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(model.equation.quote)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .hoverSource(.cited(card: cardID, index: 0))
            }

            chart
                .frame(height: card.comparesCups ? 210 : 220)

            conditionChips
            selectedLine
            if card.comparesCups { cups } else { ownMath }
            Spacer(minLength: 0)
            Text(card.comparesCups ? "Dashed: what the paper predicts for that cup · solid: what it did"
                                   : "Twist for k · swipe for the next condition · push into the cup chart to compare")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: Chart

    private var chart: some View {
        Chart {
            if card.comparesCups {
                ForEach(benchCups, id: \.cup) { bench in
                    ForEach(bench.points, id: \.time) { point in
                        LineMark(x: .value("Time", point.time), y: .value("°C", point.celsius), series: .value("Cup", "cup \(bench.cup.rawValue)"))
                            .foregroundStyle(color(bench.cup))
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                    }
                    ForEach(bench.prediction, id: \.time) { point in
                        LineMark(x: .value("Time", point.time), y: .value("°C", point.celsius), series: .value("Cup", "paper \(bench.cup.rawValue)"))
                            .foregroundStyle(color(bench.cup).opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                }
            } else {
                ForEach(Array(model.conditions.enumerated()), id: \.offset) { index, condition in
                    let selected = index == card.selected
                    ForEach(curve(k: selected ? card.k : condition.k.value), id: \.time) { point in
                        LineMark(x: .value("Time", point.time), y: .value("°C", point.celsius), series: .value("Condition", condition.name))
                            .foregroundStyle(selected ? Theme.accent : Theme.muted.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: selected ? 3 : 1))
                    }
                }
                if card.twistedK != nil {
                    ForEach(curve(k: card.condition.k.value), id: \.time) { point in
                        LineMark(x: .value("Time", point.time), y: .value("°C", point.celsius), series: .value("Condition", "paper's k"))
                            .foregroundStyle(Theme.accent.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                }
                ForEach(Array(model.checks.enumerated()), id: \.offset) { _, check in
                    if check.reported.kind == .timeTo {
                        PointMark(x: .value("Time", check.reported.value.value), y: .value("°C", check.reported.at))
                            .foregroundStyle(check.matches ? Theme.ink : Theme.warn)
                            .symbolSize(check.matches ? 30 : 70)
                        if !check.matches {
                            PointMark(x: .value("Time", check.expected), y: .value("°C", check.reported.at))
                                .foregroundStyle(Theme.warn.opacity(0.5))
                                .symbol(.circle)
                                .symbolSize(70)
                        }
                    }
                }
            }
        }
        .chartXScale(domain: 0...timeSpan)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel {
                    if let time = value.as(Double.self) { Text("\(PaperModelText.number(time)) \(model.timeUnit)") }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel {
                    if let celsius = value.as(Double.self) { Text("\(Int(celsius))°") }
                }
            }
        }
    }

    private struct Point {
        var time: Double
        var celsius: Double
    }

    private var timeSpan: Double {
        if card.comparesCups {
            let longest = benchCups.map { $0.points.last?.time ?? 0 }.max() ?? 0
            return max(longest * 1.4, 3)
        }
        let reported = model.checks.flatMap { [$0.reported.value.value, $0.expected] }.max() ?? 0
        return max(reported * 1.15, 10)
    }

    private func curve(k: Double, from start: Double? = nil, span: Double? = nil) -> [Point] {
        let span = span ?? timeSpan
        return (0...48).map { step in
            let time = span * Double(step) / 48
            let room = model.room?.value ?? 0
            let celsius = start.map { room + ($0 - room) * exp(-k * time) } ?? model.value(after: time, k: k)
            return Point(time: time, celsius: celsius)
        }
    }

    // MARK: Conditions

    private var conditionChips: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.conditions.enumerated()), id: \.offset) { index, condition in
                let selected = index == card.selected
                let wrong = model.mismatches.contains { $0.condition == condition.name }
                Text(condition.name)
                    .font(.system(size: 11, weight: selected ? .bold : .medium))
                    .foregroundStyle(selected ? Theme.paper : (wrong ? Theme.warn : Theme.ink))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(selected ? Theme.accent : Theme.line))
                    .onTapGesture { canvas.selectCondition(index, in: cardID) }
            }
        }
    }

    private var selectedLine: some View {
        let condition = card.condition
        let target = model.checks.first { $0.condition == condition.name && $0.reported.kind == .timeTo }?.reported.at
        let reach = target.flatMap { model.time(to: $0, k: card.k) }
        let index = 1 + card.selected
        return HStack(spacing: 6) {
            Text(String(format: "k = %.3f per %@", card.k, model.timeUnit))
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.ink)
            Text(card.twistedK == nil
                 ? "as printed" + (condition.spread.map { String(format: " (± %.3f)", $0) } ?? "")
                 : String(format: "twisted from %.3f", condition.k.value))
                .font(.system(size: 12))
                .foregroundStyle(card.twistedK == nil ? Theme.muted : Theme.hot)
                .hoverSource(.cited(card: cardID, index: index))
            Spacer(minLength: 4)
            if let reach, let target {
                Text("reaches \(PaperModelText.number(target))° at \(PaperModelText.number(reach)) \(model.timeUnit)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    // MARK: The paper's own math

    private var ownMath: some View {
        let checks = model.checks
        let following = checks.filter(\.matches).count
        let firstCheck = 1 + model.conditions.count
        return VStack(alignment: .leading, spacing: 4) {
            Text("THE PAPER'S OWN MATH")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(model.mismatches.isEmpty ? Theme.accent : Theme.warn)
            Text("\(following) of \(checks.count) reported results follow from its own equation and k.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink)
            ForEach(Array(checks.enumerated()).filter { !$0.element.matches }.prefix(2), id: \.offset) { offset, check in
                Text("\(check.condition): the table says \(PaperModelText.number(check.reported.value.value)) \(model.timeUnit), but its k = \(PaperModelText.number(model.conditions.first { $0.name == check.condition }?.k.value ?? 0)) gives \(PaperModelText.number(check.expected)).")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.warn)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .hoverSource(.cited(card: cardID, index: firstCheck + offset))
            }
        }
    }

    // MARK: Your cups

    private struct BenchCup {
        var cup: Cup
        var points: [Point]
        var prediction: [Point]
        var fit: FittedRate?
        var nearest: PaperModel.Condition?
    }

    /// Each cup that's been poured: its cooling since the pour, and the paper's prediction from the same start.
    private var benchCups: [BenchCup] {
        let room = model.room?.value ?? 21
        return Cup.allCases.compactMap { cup in
            let segment = FittedRate.segment(probes.history[cup] ?? [])
            guard let first = segment.first, first.celsius > room + 10 else { return nil }
            let stride = max(1, segment.count / 120)
            let points = segment.enumerated().filter { $0.offset % stride == 0 }.map {
                Point(time: ($0.element.time - first.time) / unitSeconds, celsius: $0.element.celsius)
            }
            let fit = FittedRate.cooling(segment, room: room)
            let perUnit = fit.map { $0.k * unitSeconds / 60 }
            let nearest = perUnit.flatMap { k in model.conditions.min { abs($0.k.value - k) < abs($1.k.value - k) } }
            let span = max((points.last?.time ?? 0) * 1.4, 3)
            let prediction = nearest.map { curve(k: $0.k.value, from: first.celsius, span: span) } ?? []
            return BenchCup(cup: cup, points: points, prediction: prediction, fit: fit, nearest: nearest)
        }
    }

    private var cups: some View {
        let bench = benchCups
        return VStack(alignment: .leading, spacing: 4) {
            Text("YOUR CUPS AGAINST THE PAPER")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)
            if bench.isEmpty {
                Text("Pour hot water into a cup and Grasp fits its k as it cools.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            ForEach(bench, id: \.cup) { cup in
                HStack(spacing: 6) {
                    Circle().fill(color(cup.cup)).frame(width: 8, height: 8)
                    Text(line(for: cup))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
            }
        }
    }

    private func line(for cup: BenchCup) -> String {
        guard let fit = cup.fit, let nearest = cup.nearest else {
            return "Cup \(cup.cup.rawValue): measuring… needs about 20 s of cooling"
        }
        let factor = unitSeconds / 60
        let k = fit.k * factor, error = fit.standardError * factor
        let verdict = fit.isConsistent(with: nearest.k.value / factor, spread: nearest.spread.map { $0 / factor })
            ? "consistent" : "differs"
        return String(format: "Cup %@: k %.4f ± %.4f · closest %@ (%.3f) · %@", cup.cup.rawValue, k, error,
                      nearest.name, nearest.k.value, verdict)
    }

    private func color(_ cup: Cup) -> Color {
        switch cup {
        case .a: Theme.warn
        case .b: Theme.accent
        case .c: Theme.cool
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
