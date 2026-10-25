import Foundation

/// The line burned into each frame of a run's time-lapse: when it is, what was being done, and
/// each cup's reading then. "0:36 · Poured hot water into cup A · A 44.2 °C · B 45.0 °C"
public enum TimeLapseCaption {
    public static func caption(at seconds: Double, notebook: LabNotebook, readings: [Reading]) -> String {
        var parts = [clockTime(seconds)]
        if let step = notebook.steps.last(where: { $0.seconds <= seconds + 1 }) { parts.append(step.did) }
        for cup in Cup.allCases {
            // The nearest reading within a few seconds; a cup with no probe is left out.
            let near = readings.filter { $0.cup == cup && abs($0.time - seconds) <= 3 }
                .min { abs($0.time - seconds) < abs($1.time - seconds) }
            if let near { parts.append("\(cup.rawValue) \(String(format: "%.1f", near.celsius)) °C") }
        }
        return parts.joined(separator: " · ")
    }
}
