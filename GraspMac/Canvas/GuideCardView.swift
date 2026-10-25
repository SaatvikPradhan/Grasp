import GraspKit
import SwiftUI

/// A protocol, step by step: the step you're on, read aloud, with what Grasp is watching for
/// (a probe, a temperature, a timer, or your "done"); the cups now; every step with when it was
/// done and how Grasp knew; and anything that went differently from the page.
struct GuideCardView: View {
    let cardID: UUID
    let card: GuideCard
    let guide: ProtocolGuide
    let probes: ProbeHub

    private var run: ProtocolRun? { guide.run ?? guide.lastRun }
    private var celsius: [Cup: Double] { probes.latest.filter { !probes.isStale($0.key) }.mapValues(\.celsius) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("GUIDED RUN")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    if guide.isRunning {
                        HStack(spacing: 5) {
                            Circle().fill(Theme.warn).frame(width: 7, height: 7)
                            Text(clockTime(guide.elapsed))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.warn)
                        }
                    }
                }
                Text(card.lab.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }

            current
                .frame(height: 120, alignment: .topLeading)

            HStack(spacing: 18) {
                ForEach(Cup.allCases) { cup in
                    Text(celsius[cup].map { String(format: "%@ %.1f°", cup.rawValue, $0) } ?? "\(cup.rawValue) —")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(celsius[cup] == nil ? Theme.muted : Theme.ink)
                }
            }
            .frame(height: 24)

            Text("STEPS")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .frame(height: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(card.lab.steps.enumerated()), id: \.offset) { index, step in
                    row(index, step)
                        .frame(height: 22)
                        .hoverSource(.cited(card: cardID, index: index))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                if let deviations = run?.deviations, !deviations.isEmpty {
                    Text("DIFFERENT FROM THE PAGE")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.hot)
                    ForEach(Array(deviations.suffix(2).enumerated()), id: \.offset) { _, deviation in
                        Text("\(clockTime(deviation.seconds))  \(deviation.text)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.hot)
                            .lineLimit(1)
                    }
                }
            }
            .frame(height: 56, alignment: .topLeading)

            Spacer(minLength: 0)
            Text("Say \u{201C}done\u{201D} or press the button · \u{201C}we're done\u{201D} writes it up")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var current: some View {
        if let run, let step = run.step {
            let waiting = run.waiting(celsius, at: guide.elapsed)
            VStack(alignment: .leading, spacing: 6) {
                Text("STEP \(step.number) OF \(card.lab.steps.count)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                Text(step.instruction)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    // A cup with no probe on this bench: the camera or your word moves it on.
                    Image(systemName: ProtocolRun.cup(of: step.check).map { celsius[$0] == nil } == true ? "eye" : icon(step.check))
                        .foregroundStyle(Theme.hot)
                    Text(waiting.text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
                if let fraction = waiting.fraction {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.line)
                        Capsule().fill(Theme.hot).frame(width: 440 * fraction)
                    }
                    .frame(width: 440, height: 6)
                }
                // What the bench camera sees now: steps the probes can't check finish when it sees them done.
                if let seeing = guide.seeing {
                    HStack(spacing: 8) {
                        Image(systemName: "eye")
                            .foregroundStyle(Theme.accent)
                        Text("Grasp sees: \(seeing)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
            }
        } else if let run {
            VStack(alignment: .leading, spacing: 6) {
                Text("DONE")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                Text("\(run.done.count) of \(card.lab.steps.count) steps in \(clockTime(run.done.last?.finished ?? guide.elapsed))")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(run.deviations.isEmpty ? "Everything went as the page says. The notebook has the times."
                     : "\(run.deviations.count) thing\(run.deviations.count == 1 ? "" : "s") went differently from the page; the notebook lists them.")
                    .font(.system(size: 13))
                    .foregroundStyle(run.deviations.isEmpty ? Theme.muted : Theme.hot)
            }
        } else if guide.isReading {
            Text("Reading the protocol…")
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ready: \(card.lab.steps.count) steps")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Say \u{201C}I'm starting the experiment\u{201D} or press \u{2318}\u{21E7}G. Grasp reads each step aloud, watches the probes, and times everything.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ index: Int, _ step: LabProtocol.Step) -> some View {
        let done = run?.done.first { $0.step == index }
        let isCurrent = run?.current == index
        return HStack(spacing: 8) {
            Image(systemName: done != nil ? "checkmark.circle.fill" : (isCurrent ? "play.circle.fill" : "circle"))
                .font(.system(size: 12))
                .foregroundStyle(done != nil ? Theme.accent : (isCurrent ? Theme.hot : Theme.muted))
            Text("\(step.number)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .frame(width: 14, alignment: .trailing)
            Text(step.instruction)
                .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(done == nil && !isCurrent ? Theme.muted : Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let done {
                Text("\(clockTime(done.finished)) · \(how(done.how))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private func how(_ how: ProtocolRun.How) -> String {
        switch how {
        case .probe(let text): text.replacingOccurrences(of: "probe ", with: "")
        case .timer: "timer"
        case .said: "you said"
        case .camera: "camera saw it"
        }
    }

    private func icon(_ check: LabProtocol.Step.Check) -> String {
        switch check {
        case .sayDone: "mic"
        case .rises, .drops: "thermometer.medium"
        case .below, .above: "thermometer.snowflake"
        case .wait: "timer"
        }
    }
}
