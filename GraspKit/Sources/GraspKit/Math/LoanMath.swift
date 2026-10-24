import Foundation

public enum LoanMath {
    /// Monthly payment `M = P·r / (1 − (1 + r)^(−n))`, with `r = APR / 12` and `n` months.
    public static func monthlyPayment(principal: Double, apr: Double, months: Int) -> Double {
        guard months > 0 else { return principal }
        let n = Double(months)
        let r = apr / 12
        guard r != 0 else { return principal / n }
        return principal * r / (1 - pow(1 + r, -n))
    }
}
