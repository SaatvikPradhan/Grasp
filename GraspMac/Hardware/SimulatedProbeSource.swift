import Foundation
import GraspKit

/// Fake cup temperatures once a second, so research work and rehearsals don't wait on hardware.
/// Each reading is written as a protocol line and parsed back, exactly as a board's would be.
@MainActor
final class SimulatedProbeSource: ProbeSource {
    let name = "Simulated probes"
    private(set) var isConnected = false
    var onReading: ((Reading) -> Void)?

    private let bench: SimulatedBench
    private var timer: Timer?
    private var startedAt = 0.0

    init(bench: SimulatedBench = SimulatedBench()) {
        self.bench = bench
    }

    func start() {
        guard timer == nil else { return }
        startedAt = ProcessInfo.processInfo.systemUptime
        isConnected = true
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isConnected = false
    }

    /// There's no strip to light.
    func send(_ command: String) {}

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        for cup in Cup.allCases {
            let line = ProbeProtocol.temperature(cup, bench.celsius(cup, after: now - startedAt))
            guard case .temperature(let cup, let celsius)? = ProbeProtocol.parse(line) else { continue }
            onReading?(Reading(cup: cup, celsius: celsius, time: now))
        }
    }
}
