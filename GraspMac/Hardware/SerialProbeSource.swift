import Foundation
import GraspKit

/// The Pico W bench over USB (firmware/pico/main.py). Finds the board by itself: every USB serial
/// device is opened and sent `PING`, and the first one that sends a protocol line (`PONG`, or the
/// `T` lines it prints every second) is kept. While it's unplugged, the hub keeps the last readings
/// (shown as stale) and this looks again every 2 s, so plugging it back in needs no restart.
@MainActor
final class SerialProbeSource: ProbeSource {
    private(set) var name = "Pico bench · looking for the board"
    private(set) var isConnected = false
    var onReading: ((Reading) -> Void)?
    /// Room air from the board's DHT11.
    var onRoom: ((Double) -> Void)?
    /// A cup just dropped below the board's target temperature.
    var onAlert: ((Cup) -> Void)?
    /// A board answered; the hub switches to it.
    var onConnect: (() -> Void)?
    /// The board was unplugged.
    var onDisconnect: (() -> Void)?

    private var port: SerialPort?
    /// Devices sent `PING` that haven't said anything yet, by path.
    private var trying: [String: SerialPort] = [:]
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.port == nil, self.trying.isEmpty else { return }
                self.scan()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        port?.close()
        trying.values.forEach { $0.close() }
        port = nil
        trying = [:]
        isConnected = false
    }

    /// The Pico bench has a buzzer and an LCD but no LED strip: a `FLASH` becomes a beep,
    /// and `LED` and `METER` are dropped. Everything else goes through as is.
    func send(_ command: String) {
        if command.hasPrefix("FLASH,") {
            port?.write(ProbeProtocol.beep)
        } else if command.hasPrefix("LED,") || command.hasPrefix("METER,") {
            return
        } else {
            port?.write(command)
        }
    }

    private func scan() {
        let devices = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        let paths = devices
            .filter { name in
                ["cu.usbmodem", "cu.usbserial", "cu.SLAB_USBtoUART", "cu.wchusbserial"].contains { name.hasPrefix($0) }
            }
            .map { "/dev/" + $0 }
        for path in paths where trying[path] == nil {
            let opened = SerialPort(path: path, onLine: { [weak self] line in
                self?.heard(line, from: path)
            }, onClose: { [weak self] in
                self?.closed(path)
            })
            guard let opened else { continue }
            trying[path] = opened
            opened.write(ProbeProtocol.ping)
        }
        // A device that says nothing in 3 s isn't the bench.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            for (path, silent) in self.trying where path != self.port?.path {
                silent.close()
            }
            self.trying = [:]
        }
    }

    private func heard(_ line: String, from path: String) {
        guard let message = ProbeProtocol.parse(line) else { return }
        if port == nil, let candidate = trying.removeValue(forKey: path) {
            adopt(candidate)
        }
        guard port?.path == path else { return }

        switch message {
        case .temperature(let cup, let celsius):
            onReading?(Reading(cup: cup, celsius: celsius, time: ProcessInfo.processInfo.systemUptime))
        case .room(let celsius):
            onRoom?(celsius)
        case .alert(let cup):
            onAlert?(cup)
        case .ready, .pong, .address, .error, .calibrated:
            break
        }
    }

    private func adopt(_ found: SerialPort) {
        port = found
        trying.values.forEach { $0.close() }
        trying = [:]
        isConnected = true
        name = "Pico W · " + found.path.replacingOccurrences(of: "/dev/", with: "")
        onConnect?()
    }

    private func closed(_ path: String) {
        if port?.path == path {
            port = nil
            isConnected = false
            name = "Pico bench · unplugged, plug it back in"
            onDisconnect?()
        } else {
            trying.removeValue(forKey: path)
        }
    }
}
