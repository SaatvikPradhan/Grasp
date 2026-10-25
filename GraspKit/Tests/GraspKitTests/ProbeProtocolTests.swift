import Foundation
import Testing
@testable import GraspKit

struct ProbeProtocolTests {
    @Test func parsesEveryMessage() {
        #expect(ProbeProtocol.parse("READY") == .ready)
        #expect(ProbeProtocol.parse("PONG") == .pong)
        #expect(ProbeProtocol.parse("ADDR,A,28FF641E8216035C") == .address(cup: .a, rom: "28FF641E8216035C"))
        #expect(ProbeProtocol.parse("T,B,21.50") == .temperature(cup: .b, celsius: 21.5))
        #expect(ProbeProtocol.parse("T,C,-3.25") == .temperature(cup: .c, celsius: -3.25))
        #expect(ProbeProtocol.parse("ERR,C,disconnected") == .error(cup: .c, reason: "disconnected"))
    }

    @Test func toleratesLineEndingsAndSpaces() {
        #expect(ProbeProtocol.parse("T,A,38.25\r\n") == .temperature(cup: .a, celsius: 38.25))
        #expect(ProbeProtocol.parse("  T, A , 38.25 ") == .temperature(cup: .a, celsius: 38.25))
        #expect(ProbeProtocol.parse("READY\r") == .ready)
    }

    @Test func rejectsGarbage() {
        #expect(ProbeProtocol.parse("") == nil)
        #expect(ProbeProtocol.parse("T,A") == nil)          // cut off mid-line
        #expect(ProbeProtocol.parse("T,A,") == nil)
        #expect(ProbeProtocol.parse("T,A,abc") == nil)
        #expect(ProbeProtocol.parse("T,D,20") == nil)       // no cup D
        #expect(ProbeProtocol.parse("T,A,-127.00") == nil)  // DS18B20's "disconnected" value
        #expect(ProbeProtocol.parse("T,A,20,extra") == nil)
        #expect(ProbeProtocol.parse("HELLO") == nil)
    }

    @Test func simulatorLinesParseBack() {
        let line = ProbeProtocol.temperature(.a, 38.254)
        #expect(line == "T,A,38.25\n")
        #expect(ProbeProtocol.parse(line) == .temperature(cup: .a, celsius: 38.25))
    }

    @Test func commandsClampTheirValues() {
        #expect(ProbeProtocol.led(r: 300, g: -5, b: 128) == "LED,255,0,128\n")
        #expect(ProbeProtocol.flash(r: 0, g: 0, b: 255, ms: 300) == "FLASH,0,0,255,300\n")
        #expect(ProbeProtocol.meter(0.624) == "METER,0.62\n")
        #expect(ProbeProtocol.meter(1.7) == "METER,1.00\n")
    }
}

struct SimulatedBenchTests {
    let bench = SimulatedBench(noise: 0)

    @Test func cupsStartWhereTheDemoDoes() {
        #expect(bench.celsius(.a, after: 0) == 40)
        #expect(bench.celsius(.c, after: 0) == 6)
        #expect(abs(bench.celsius(.b, after: 0) - 21.5) < 0.01)
    }

    @Test func warmCupCoolsAndColdCupWarmsTowardTheRoom() {
        let a1 = bench.celsius(.a, after: 60), a2 = bench.celsius(.a, after: 600)
        #expect(a1 < 40 && a2 < a1 && a2 > 21)
        let c1 = bench.celsius(.c, after: 60), c2 = bench.celsius(.c, after: 600)
        #expect(c1 > 6 && c2 > c1 && c2 < 21)
    }

    @Test func oneTimeConstantClosesTwoThirdsOfTheGap() {
        // After τ the gap to the room is e⁻¹ ≈ 36.8% of where it started.
        let gap = bench.celsius(.a, after: 900) - 21
        #expect(abs(gap - 19 * exp(-1)) < 0.001)
    }

    @Test func noiseStaysSmall() {
        let noisy = SimulatedBench()
        for _ in 0..<200 {
            #expect(abs(noisy.celsius(.b, after: 0) - 21.5) <= 0.05 + 1e-9)
        }
    }
}
