import Foundation

/// Finds a number among the lines Vision read off a page, however it was printed: 6.2 as "6.2"
/// or "6.20", 1150 as "1,150" or "1,150.00". A number Gemini reports only counts if it's here.
public enum PrintedNumber {
    /// The first line the number is printed on.
    public static func line(of number: Double, in lines: [String]) -> Int? {
        let forms = forms(of: number)
        return lines.firstIndex { line in
            let digits = line.replacingOccurrences(of: ",", with: "")
            return forms.contains { contains($0, in: digits) }
        }
    }

    static func forms(of number: Double) -> [String] {
        let value = abs(number)
        let short = String(value).replacing(#/\.0$/#, with: "")
        let plain = value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
        // Trailing zeros as printed: 0.03 as "0.030", 30 as "30.0".
        let padded = (1...4).map { String(format: "%.\($0)f", value) }.filter { Double($0) == value }
        return [String(format: "%.2f", value), plain, short] + padded
    }

    /// True when `number` appears in `text` on its own, not as part of a longer number.
    static func contains(_ number: String, in text: String) -> Bool {
        var start = text.startIndex
        while let range = text.range(of: number, range: start..<text.endIndex) {
            let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : " "
            let after = range.upperBound < text.endIndex ? text[range.upperBound] : " "
            if !before.isNumber, before != ".", !after.isNumber { return true }
            start = range.upperBound
        }
        return false
    }
}
