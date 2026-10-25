import Foundation

/// A scripted 2½-minute session for rehearsing the lab notebook without a bench: hot water into
/// cup A at 0:10, a lid on B at 0:58, ice into C at 1:28, with what someone said as they did it.
public enum LabRehearsal {
    public static let duration = 150.0
    static let room = 22.0

    public static func recording(frames: [LabRecording.Frame] = []) -> LabRecording {
        var random = SeededNoise(seed: 7)
        var readings: [Reading] = []
        for second in 0...Int(duration) {
            let t = Double(second)
            for cup in Cup.allCases {
                readings.append(Reading(cup: cup, celsius: celsius(cup, at: t) + random.next() * 0.15, time: t))
            }
        }
        return LabRecording(frames: frames, speech: speech, readings: readings, duration: duration)
    }

    public static let speech: [LabRecording.Line] = [
        .init(seconds: 3, text: "Okay recording, three cups with probes in A B and C"),
        .init(seconds: 9, text: "Pouring the hot water into cup A now"),
        .init(seconds: 31, text: "B is already hot from before so I'm leaving it open for now"),
        .init(seconds: 57, text: "Putting the lid on B"),
        .init(seconds: 87, text: "Let's see what ice does, two cubes into C"),
        .init(seconds: 101, text: "Whoa C dropped fast"),
        .init(seconds: 138, text: "A is still way hotter than C"),
        .init(seconds: 146, text: "Okay stopping here"),
    ]

    static func celsius(_ cup: Cup, at t: Double) -> Double {
        switch cup {
        case .a:
            // Room temperature until the pour at 0:10, which takes three seconds.
            guard t > 10 else { return room }
            let poured = 88.0
            if t < 13 { return room + (poured - room) * (t - 10) / 3 }
            return NewtonCooling.temperature(start: poured, ambient: room, tau: 300, after: t - 13)
        case .b:
            // Open until the lid at 0:58, then much slower.
            let atLid = NewtonCooling.temperature(start: 80, ambient: room, tau: 250, after: 58)
            guard t > 58 else { return NewtonCooling.temperature(start: 80, ambient: room, tau: 250, after: t) }
            return NewtonCooling.temperature(start: atLid, ambient: room, tau: 1_000, after: t - 58)
        case .c:
            // Ice at 1:28 takes 20 degrees off over six seconds.
            let atIce = NewtonCooling.temperature(start: 70, ambient: room, tau: 300, after: 88)
            guard t > 88 else { return NewtonCooling.temperature(start: 70, ambient: room, tau: 300, after: t) }
            if t < 94 { return atIce - 20 * (t - 88) / 6 }
            return NewtonCooling.temperature(start: atIce - 20, ambient: room, tau: 300, after: t - 94)
        }
    }
}

/// Small repeatable noise in -1...1, so a rehearsal reads the same every time.
struct SeededNoise {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53) * 2 - 1
    }
}
