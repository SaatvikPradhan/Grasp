import Foundation
import GraspKit
import Observation

/// Owns the probe source and keeps the recent readings for charts.
@MainActor @Observable
final class ProbeHub {
    /// Seconds of history kept per cup.
    static let window = 120.0
    /// A cup with no reading for this long is shown as stale.
    static let staleAfter = 3.0

    private(set) var history: [Cup: [Reading]] = [:]
    private(set) var latest: [Cup: Reading] = [:]
    private(set) var sourceName = ""
    private(set) var isSimulated = true

    // When the board works, the swap is here: SerialProbeSource() instead (see docs/SENSORS.md).
    @ObservationIgnored private var source: ProbeSource = SimulatedProbeSource()
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        source.onReading = { [weak self] reading in
            self?.record(reading)
        }
        source.start()
        sourceName = source.name
        isSimulated = source is SimulatedProbeSource
    }

    /// Sends a `ProbeProtocol` command (LED, FLASH, METER) to the board, if there is one.
    func send(_ command: String) {
        source.send(command)
    }

    /// Time of the newest reading from any cup; charts measure "seconds ago" from here.
    var now: Double {
        latest.values.map(\.time).max() ?? ProcessInfo.processInfo.systemUptime
    }

    func isStale(_ cup: Cup) -> Bool {
        guard let reading = latest[cup] else { return true }
        return ProcessInfo.processInfo.systemUptime - reading.time > Self.staleAfter
    }

    private func record(_ reading: Reading) {
        latest[reading.cup] = reading
        var readings = history[reading.cup, default: []]
        readings.append(reading)
        readings.removeAll { reading.time - $0.time > Self.window }
        history[reading.cup] = readings
    }
}
