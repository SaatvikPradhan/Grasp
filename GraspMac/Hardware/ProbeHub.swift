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
    /// The bench beeps three times and sends `ALERT` when a cup drops below this (the 37 °C demo).
    static let alertBelow = 37.0

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
    /// Room air from the bench's DHT11, once the board sends it.
    private(set) var room: Double?

    /// Simulated until the Pico bench answers over USB, then the board for good: if it's unplugged,
    /// its last readings stay on the chart as stale until it's plugged back in.
    @ObservationIgnored private var source: ProbeSource = SimulatedProbeSource()
    @ObservationIgnored private var board: SerialProbeSource?
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        use(source)
        // Snapshot runs are checks: they leave the bench (and the copy of Grasp using it) alone,
        // unless GRASP_SNAPSHOT_BOARD is set.
        let environment = ProcessInfo.processInfo.environment
        if environment["GRASP_SNAPSHOT"] != nil, environment["GRASP_SNAPSHOT_BOARD"] == nil { return }
        let board = SerialProbeSource()
        board.onRoom = { [weak self] celsius in self?.room = celsius }
        board.onAlert = { [weak self] cup in
            self?.mark("Cup \(cup.rawValue) below \(String(format: "%.0f", Self.alertBelow)) °C")
        }
        board.onConnect = { [weak self, weak board] in
            guard let self, let board else { return }
            if self.source !== board {
                self.source.stop()
                // The simulated readings aren't the bench's: start the chart fresh.
                self.history = [:]
                self.latest = [:]
                self.markers = []
                self.use(board)
            }
            self.sourceName = board.name
            board.send(ProbeProtocol.target(Self.alertBelow))
        }
        board.onDisconnect = { [weak self, weak board] in
            guard let self, let board else { return }
            self.sourceName = board.name
        }
        board.start()
        self.board = board
    }

    private func use(_ new: ProbeSource) {
        source = new
        new.onReading = { [weak self] reading in
            self?.record(reading)
        }
        if new is SimulatedProbeSource { new.start() }
        sourceName = new.name
        isSimulated = new is SimulatedProbeSource
    }

    /// Makes the bench's two thermistors read the same. Put both probes in the same cup first.
    func calibrate() {
        source.send(ProbeProtocol.calibrate)
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

    /// Sends a `ProbeProtocol` command to the board, if there is one (on the Pico bench a FLASH beeps).
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
