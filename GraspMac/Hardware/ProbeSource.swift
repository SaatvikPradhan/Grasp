import GraspKit

/// Where cup temperatures come from: the real board over USB, or the simulator.
/// The rest of the app only talks to this, so swapping sources is one line in `ProbeHub`.
@MainActor
protocol ProbeSource: AnyObject {
    /// Shown under the chart, for example "Simulated probes" or "ESP32 · /dev/cu.usbserial-0001".
    var name: String { get }
    var isConnected: Bool { get }
    var onReading: ((Reading) -> Void)? { get set }
    func start()
    func stop()
    /// A Mac → board command from `ProbeProtocol` (LED, FLASH, METER).
    func send(_ command: String)
}
