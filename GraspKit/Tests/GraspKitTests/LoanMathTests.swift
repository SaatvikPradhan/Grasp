import Testing
@testable import GraspKit

/// The loan table in GRASP.md section 7 is what the demo says out loud, so it must match.
struct LoanMathTests {
    let contract = LoanTerms.demoContract

    @Test func seventyTwoMonthPitch() {
        #expect(abs(contract.monthlyPayment - 388.28) < 0.01)
        #expect(abs(contract.totalPaid - 27_956) < 1)
        #expect(abs(contract.totalInterest - 6_356) < 1)
    }

    @Test func shorterTermsSave() {
        let sixty = contract.with(termMonths: 60)
        #expect(abs(sixty.monthlyPayment - 447.33) < 0.01)
        #expect(abs(contract.totalPaid - sixty.totalPaid - 1_116) < 1)

        let fortyEight = contract.with(termMonths: 48)
        #expect(abs(fortyEight.monthlyPayment - 536.49) < 0.01)
        #expect(abs(fortyEight.totalInterest - 4_152) < 1)
        #expect(abs(contract.totalPaid - fortyEight.totalPaid - 2_204) < 1)
    }

    @Test func creditUnionQuote() {
        let creditUnion = LoanTerms(principal: 21_600, apr: 0.064, termMonths: 48)
        #expect(abs(creditUnion.monthlyPayment - 511.25) < 0.01)
        #expect(abs(contract.totalPaid - creditUnion.totalPaid - 3_416) < 1)
    }

    @Test func zeroRateSplitsEvenly() {
        #expect(LoanMath.monthlyPayment(principal: 1_200, apr: 0, months: 12) == 100)
    }
}

struct OneEuroFilterTests {
    @Test func stillValueStaysPut() {
        var filter = OneEuroFilter(minCutoff: 1, beta: 0)
        for frame in 0..<30 {
            #expect(filter.filter(0.5, at: Double(frame) / 30) == 0.5)
        }
    }

    @Test func jitterShrinks() {
        var filter = OneEuroFilter(minCutoff: 1, beta: 0)
        var outputs: [Double] = []
        for frame in 0..<120 {
            let noisy = 0.5 + (frame.isMultiple(of: 2) ? 0.01 : -0.01)
            outputs.append(filter.filter(noisy, at: Double(frame) / 30))
        }
        let tail = outputs.suffix(30)
        #expect(tail.max()! - tail.min()! < 0.01)
    }
}
