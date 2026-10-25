import Foundation
import GraspKit
import Observation

/// Owns the probe source and keeps the recent readings for charts.
@MainActor @Observable
final class ProbeHub {
    /// Seconds of history the live chart shows.
    static let window = 120.0
    /// Seconds of history kept per cup, for fitting and comparing.
    static let kept = 1_800.0
    /// A cup with no reading for this long is shown as stale.
    static let staleAfter = 3.0

    private(set) var history: [Cup: [Reading]] = [:]
    private(set) var latest: [Cup: Reading] = [:]
    private(set) var sourceName = ""
    /// Labelled moments on the live chart: a protocol step done, a pour.
    private(set) var markers: [Marker] = []

    struct Marker: Equatable, Identifiable {
        var time: Double
        var label: String
        var id: Double { time }
    }
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

    /// Pours, lids or ices a simulated cup. Returns false on real probes, which need real hands.
    @discardableResult
    func simulate(_ action: SimulatedBench.Action) -> Bool {
        guard let simulated = source as? SimulatedProbeSource else { return false }
        simulated.apply(action)
        return true
    }

    /// Puts a labelled marker on the live chart, now.
    func mark(_ label: String) {
        markers.append(Marker(time: now, label: label))
        markers.removeAll { now - $0.time > Self.kept }
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
        readings.removeAll { reading.time - $0.time > Self.kept }
        history[reading.cup] = readings
    }
}
