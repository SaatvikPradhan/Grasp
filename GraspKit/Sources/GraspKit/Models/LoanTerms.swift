import Foundation

/// A fixed-rate installment loan, as read off a contract.
public struct LoanTerms: Codable, Hashable, Sendable {
    /// Amount financed, in dollars.
    public var principal: Double
    /// Annual percentage rate as a fraction: 0.089 for 8.9%.
    public var apr: Double
    public var termMonths: Int

    public init(principal: Double, apr: Double, termMonths: Int) {
        self.principal = principal
        self.apr = apr
        self.termMonths = termMonths
    }

    public var monthlyPayment: Double {
        LoanMath.monthlyPayment(principal: principal, apr: apr, months: termMonths)
    }

    public var totalPaid: Double { monthlyPayment * Double(termMonths) }

    public var totalInterest: Double { totalPaid - principal }

    public func with(termMonths: Int) -> LoanTerms {
        LoanTerms(principal: principal, apr: apr, termMonths: termMonths)
    }

    public func with(apr: Double) -> LoanTerms {
        LoanTerms(principal: principal, apr: apr, termMonths: termMonths)
    }
}

extension LoanTerms {
    /// The demo contract from GRASP.md: $21,600 financed at 8.9% for 72 months.
    public static let demoContract = LoanTerms(principal: 21_600, apr: 0.089, termMonths: 72)
}
