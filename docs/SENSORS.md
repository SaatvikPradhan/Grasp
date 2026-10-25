# Grasp sensors: build brief

You're building the live-data half of Grasp: three temperature probes on a board, the code that gets their readings onto the Mac, and a live chart. This covers gate **G4** and the start of Research mode from the build plan. Read [`GRASP.md`](../GRASP.md) for the whole project. This page is everything the sensor work needs.

## Why it matters

The Research demo times an **iodine clock reaction** in three cups at three temperatures: A warm (~40 °C), B room, C cold. One probe sits in each cup. The judges watch the three temperatures live on the laptop while the cups turn dark blue one after another. Grasp then fits the activation energy from those temperatures and times. If the probes don't reach the Mac, there's no research demo, so this is on the "never cut" list.

## What to build

| # | Piece | Where | Status |
|---|---|---|---|
| 1 | **Firmware**: 3 probes out, LED commands in | `firmware/grasp_probes/grasp_probes.ino` | **Yours.** Done when Serial Monitor shows `T,A,…`, `T,B,…`, `T,C,…` once a second |
| 2 | **Protocol parser** with unit tests | `GraspKit/Sources/GraspKit/Hardware/ProbeProtocol.swift` | ✅ Built. Use it; don't rewrite it |
| 3 | **Serial port reader** on the Mac | `GraspMac/Hardware/SerialPort.swift`, `SerialProbeSource.swift` | **Yours.** Done when the board is found automatically and survives unplug and replug |
| 4 | **Simulated probe source** and `ProbeHub` | `GraspMac/Hardware/` | ✅ Built |
| 5 | **Live temperature card** | `GraspMac/Hardware/TemperatureCardView.swift` | ✅ Built. A draggable card on the canvas; ⌘T adds or removes it |

**Already working:** run the Mac app and the temperature card shows three cups moving on simulated data. **Your part:** the firmware (1), the serial reader (3), and switching `ProbeHub` to the real board (one line, see section 3). Both of your pieces have to speak the protocol below exactly.

## Hardware

From the MLH hardware table (GRASP.md section 8 has the full list):

- ESP32 dev board (or an Arduino Uno/Nano)
- 3× DS18B20 **waterproof** temperature probes, plus a spare
- 4.7 kΩ resistor (pull-up for the probe data line)
- WS2812 / NeoPixel strip, 8–16 LEDs, plus a 330 Ω resistor (optional; the firmware must work without it)
- Breadboard, jumper wires, USB cable, and a USB-C hub for the MacBook

**Test before leaving the table:** every probe reads a sensible room temperature.

### Wiring

| Part | ESP32 | Arduino Uno |
|---|---|---|
| All 3 probes, red | 3.3 V | 5 V |
| All 3 probes, black | GND | GND |
| All 3 probes, yellow (data, shared) | GPIO 4 | D2 |
| 4.7 kΩ resistor | between data and 3.3 V | between data and 5 V |
| LED strip data (through 330 Ω) | GPIO 13 | D6 |
| LED strip 5 V / GND | 5 V (VIN) / GND | 5 V / GND |

Keep the LED strip at brightness ≤ 40/255 and ≤ 16 LEDs so it runs on USB power.

## Serial protocol

USB serial at **115200 baud**, one message per line, ending in `\n`. Keep it exactly like this, because the Mac side and the simulator both speak it.

**Board → Mac**

| Line | Meaning |
|---|---|
| `READY` | Sent once after boot |
| `ADDR,A,28FF641E8216035C` | Sent after `READY` for each probe: which ROM address is cup A, B or C |
| `T,A,38.25` | Temperature of cup A in °C, 2 decimals. One line per cup, all three every second |
| `ERR,B,disconnected` | Probe B reads −127 or 85 (unplugged or not ready) |

**Mac → board** (implement now; the LED strip may not be connected)

| Line | Meaning |
|---|---|
| `LED,r,g,b` | Fill the strip with one color (0–255 each) |
| `FLASH,r,g,b,ms` | Flash that color for `ms` milliseconds, then go back to the previous fill |
| `METER,0.62` | Fill 62% of the strip red, the rest off (the "money meter") |
| `PING` | Board answers `PONG` (for checking the connection) |

Ignore unknown lines without crashing. A receipt printer (`PRINT,…` / `PRINTEND`) comes later; don't build it now.

## 1. Firmware

- Libraries: `OneWire`, `DallasTemperature`, `Adafruit_NeoPixel`. Install them from the Arduino IDE Library Manager.
- All probes share one data pin. On boot, find the 3 probes, **sort them by ROM address** and call them A, B, C. Print `READY` and the three `ADDR` lines.
- **Which probe is which cup:** hold one probe in your hand and watch which `T` line rises. Tape that cup's letter on it. Repeat for the others. Sorting by address keeps the letters stable across reboots.
- Read every second without blocking: `sensors.setWaitForConversion(false)`, call `requestTemperatures()`, and read the values on the next loop about 800 ms later. The LED `FLASH` timing must stay smooth while waiting.
- Read serial commands with a small line buffer, so a half-received line is never acted on.
- Opening the port from the Mac resets the board. That's fine: the Mac waits for `READY`.

## 2. Protocol parser (GraspKit), already built

Pure Swift in GraspKit, shared by the Mac app and the simulator, with tests in `ProbeProtocolTests.swift`. What you'll call:

```swift
ProbeProtocol.parse("T,A,38.25")      // .temperature(cup: .a, celsius: 38.25); nil for anything malformed
ProbeProtocol.baudRate                // 115_200
ProbeProtocol.ping                    // "PING\n"
ProbeProtocol.flash(r: 0, g: 0, b: 255, ms: 300)   // "FLASH,0,0,255,300\n" (values clamped)
ProbeProtocol.led(r:g:b:), ProbeProtocol.meter(0.62)

Reading(cup: .a, celsius: 38.25, time: ProcessInfo.processInfo.systemUptime)  // time = when the Mac got it
```

The parser handles `\r\n`, extra spaces, cut-off lines and bad numbers. It also rejects temperatures outside the DS18B20's −55…125 °C range, so a `-127.00` from an unplugged probe never reaches the chart.

## 3. Serial reader (Mac)

- **No third-party packages.** Use POSIX: `open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)`, `cfmakeraw`, `cfsetspeed(…, B115200)`, `tcsetattr`. Then clear `O_NONBLOCK` and read on a background queue (a `DispatchSourceRead` works well). Split the input into lines.
- **Finding the board:** look in `/dev` for `cu.usbserial*`, `cu.SLAB_USBtoUART*`, `cu.wchusbserial*` or `cu.usbmodem*`. Try each one and keep the one that sends `READY` (or answers `PING`) within 3 s.
- **Unplugged:** when a read fails, close the port, then rescan every 2 s. While it's away, the app keeps showing the last readings, marked as stale.
- The Mac app is not sandboxed, so `/dev/cu.*` can be opened directly.
- If no port shows up at all, the board may need a driver (CH340 or CP210x). Newer macOS includes them; check System Information › USB.

### Plugging into the app

Your `SerialProbeSource` conforms to the protocol in `GraspMac/Hardware/ProbeSource.swift`, which the simulator already uses:

```swift
@MainActor
protocol ProbeSource: AnyObject {
    var name: String { get }                  // "ESP32 · /dev/cu.usbserial-0001"
    var isConnected: Bool { get }
    var onReading: ((Reading) -> Void)? { get set }
    func start()
    func stop()
    func send(_ command: String)              // LED / FLASH / METER lines from ProbeProtocol
}
```

Call `onReading` on the main thread. `ProbeHub` (`GraspMac/Hardware/ProbeHub.swift`) owns the source, keeps 2 minutes of history and drives the panel. It starts with `SimulatedProbeSource()` on the line marked "When the board works, the swap is here". Change that to use your serial source when a board answers, and fall back to the simulated one when none does. `ProbeHub.isSimulated` and `sourceName` already feed the label under the chart.

## 4. Simulated source, already built

`SimulatedProbeSource` uses `SimulatedBench` (in GraspKit) and runs each reading through `ProbeProtocol` as a text line, so it exercises the same parser as the board:

- A starts at 40 °C and cools toward a 21 °C room (Newton's cooling, τ = 15 min).
- B sits near 21 °C.
- C starts at 6 °C and warms toward the room.
- Readings have ±0.05 °C of noise and arrive once a second.

## 5. Temperature card, already built

`TemperatureCardView` is a card on the canvas you can grab, move and swipe; ⌘T adds or removes it. It shows the current value of each cup, the last 2 minutes as three lines (A red, B green, C blue) or, after a swipe, as bars, and the source underneath. A cup with no reading for 3 s turns gray. **Don't change `CanvasModel` or `Card`**; they're shared with the rest of the canvas.

## G4 passes when

- [ ] With the board plugged in, three temperatures update on the Mac once a second.
- [ ] Holding a probe in your hand makes that cup's line climb within a few seconds.
- [ ] Unplugging the board marks it as stale; plugging it back in resumes without restarting the app.
- [ ] With no board, the simulated probes run and the panel says "Simulated".
- [ ] `cd GraspKit && swift test` passes, including the new protocol tests.
- [ ] Sending `FLASH,0,0,255,300` from the app flashes the strip blue, if one is connected.

## Working in the repo

- Xcode 26 on a Mac. Open `Grasp.xcodeproj` and run the **GraspMac** scheme. The firmware part works from the Arduino IDE on any computer.
- `CLAUDE.md` has the build commands and conventions: Swift 5 mode, SwiftUI with `@Observable`, no third-party dependencies, numbers computed in Swift.
- New files in `GraspMac/` are picked up automatically, with no project edits. New GraspKit files go under `GraspKit/Sources/GraspKit/`.
- No API keys are needed for this work.
- Work on a branch (`git switch -c sensors`), commit in small steps, and open a pull request.
- To avoid merge conflicts, stay out of `GraspMac/Canvas/`, `GraspMac/Hands/`, `GraspMac/Phone/` and `GraspMac/Modes/`. In `GraspMac/Hardware/`, add your new files and change only the source line in `ProbeHub.swift`.

### Using Claude Code

Open Claude Code in the repo and paste:

```
Read CLAUDE.md, GRASP.md and docs/SENSORS.md. The parser, simulated source, ProbeHub and
temperature panel are already built. Build my part: the ESP32 firmware, then the Mac serial
reader (SerialPort + SerialProbeSource), then switch ProbeHub to the real board with the
simulated fallback. Stay out of the folders the brief says to avoid. Tell me exactly what to
run and what to wire up on the breadboard.
```
