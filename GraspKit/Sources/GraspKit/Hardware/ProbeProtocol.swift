import Foundation

/// The three cups on the bench mat, one probe each.
public enum Cup: String, CaseIterable, Codable, Identifiable, Sendable {
    case a = "A", b = "B", c = "C"

    public var id: String { rawValue }
}

/// One line from the probe board. See docs/SENSORS.md for the protocol.
public enum ProbeMessage: Equatable, Sendable {
    case ready
    case address(cup: Cup, rom: String)
    case temperature(cup: Cup, celsius: Double)
    case error(cup: Cup, reason: String)
    case pong
    /// Room air from the Pico bench's DHT11, sent as `T,R,23.00`.
    case room(celsius: Double)
    /// The Pico bench: this cup just dropped below the target temperature (37 °C unless set).
    case alert(cup: Cup)
    /// The Pico bench's answer to `CAL`: the offsets it now adds to cups A and B.
    case calibrated(a: Double, b: Double)
}

/// The USB serial protocol between the probe board and the Mac: 115200 baud, one message per line.
/// The simulated source speaks it too, so both paths go through the same parser.
public enum ProbeProtocol {
    public static let baudRate = 115_200
    /// What a DS18B20 can measure; anything outside is a bad read.
    public static let validRange = -55.0...125.0

    /// Parses one board → Mac line. Returns nil for anything malformed; never traps.
    public static func parse(_ line: String) -> ProbeMessage? {
        let fields = line.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        switch (fields.first, fields.count) {
        case ("READY", 1):
            return .ready
        case ("PONG", 1):
            return .pong
        case ("ADDR", 3):
            guard let cup = Cup(rawValue: fields[1]), !fields[2].isEmpty else { return nil }
            return .address(cup: cup, rom: fields[2])
        case ("T", 3) where fields[1] == "R":
            guard let celsius = Double(fields[2]), validRange.contains(celsius) else { return nil }
            return .room(celsius: celsius)
        case ("T", 3):
            guard let cup = Cup(rawValue: fields[1]), let celsius = Double(fields[2]),
                  validRange.contains(celsius) else { return nil }
            return .temperature(cup: cup, celsius: celsius)
        case ("ERR", 3):
            guard let cup = Cup(rawValue: fields[1]) else { return nil }
            return .error(cup: cup, reason: fields[2])
        case ("ALERT", 2):
            guard let cup = Cup(rawValue: fields[1]) else { return nil }
            return .alert(cup: cup)
        case ("CAL", 3):
            guard let a = Double(fields[1]), let b = Double(fields[2]) else { return nil }
            return .calibrated(a: a, b: b)
        default:
            return nil
        }
    }

    // MARK: Board → Mac (used by the simulator)

    public static func temperature(_ cup: Cup, _ celsius: Double) -> String {
        "T,\(cup.rawValue),\(String(format: "%.2f", celsius))\n"
    }

    // MARK: Mac → board

    public static let ping = "PING\n"

    /// Fills the LED strip with one color.
    public static func led(r: Int, g: Int, b: Int) -> String {
        "LED,\(byte(r)),\(byte(g)),\(byte(b))\n"
    }

    /// Flashes a color for `ms` milliseconds, then returns to the previous fill.
    public static func flash(r: Int, g: Int, b: Int, ms: Int) -> String {
        "FLASH,\(byte(r)),\(byte(g)),\(byte(b)),\(max(ms, 0))\n"
    }

    /// Fills `fraction` of the strip red: the money meter.
    public static func meter(_ fraction: Double) -> String {
        "METER,\(String(format: "%.2f", min(max(fraction, 0), 1)))\n"
    }

    // MARK: Mac → Pico bench (firmware/pico/main.py)

    /// One short click of the buzzer.
    public static let beep = "BEEP\n"

    /// Makes both thermistors read the same. Put both probes in the same cup first.
    public static let calibrate = "CAL\n"

    /// The temperature the bench alerts below (beeps three times and sends `ALERT`).
    public static func target(_ celsius: Double) -> String {
        "TARGET,\(String(format: "%.1f", celsius))\n"
    }

    /// Shows text on the LCD's second line (16 characters); nil gives the line back to the bench.
    public static func lcd(_ text: String?) -> String {
        guard let text else { return "LCD\n" }
        let clean = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        return "LCD,\(clean.prefix(16))\n"
    }

    private static func byte(_ value: Int) -> Int {
        min(max(value, 0), 255)
    }
}
