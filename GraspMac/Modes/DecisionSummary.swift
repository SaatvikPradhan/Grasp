import AppKit
import GraspKit
import SwiftUI

/// The one-page decision summary: the offer as written, the better options, the add-ons to
/// refuse, what to say, and where the numbers came from. A letter-size PDF to print or share.
enum DecisionSummary {
    @MainActor
    static func save(facts: MoneyFacts, whatToSay: [String], to url: URL = defaultURL) -> URL? {
        let size = CGSize(width: 612, height: 792)
        let page = SummaryPage(facts: facts, whatToSay: whatToSay, date: Date())
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light)
        var saved = false
        ImageRenderer(content: page).render { _, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            saved = true
        }
        return saved ? url : nil
    }

    static var defaultURL: URL {
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop/Grasp decision summary \(stamp).pdf")
    }
}

private struct SummaryPage: View {
    let facts: MoneyFacts
    let whatToSay: [String]
    let date: Date

    private let green = Color(hex: 0x0B7A68)
    private let red = Color(hex: 0xB3261E)

    private struct Option: Identifiable {
        var name: String
        var loan: LoanTerms
        var id: String { name }
    }

    private var options: [Option] {
        var options = [Option(name: "Dealer's offer as written", loan: facts.pitch)]
        if facts.chosen.termMonths != facts.pitch.termMonths {
            options.append(Option(name: "Dealer, \(facts.chosen.termMonths) months", loan: facts.chosen))
        }
        if let quote = facts.quote {
            options.append(Option(name: "Credit union quote", loan: quote))
        }
        return options
    }

    private var best: String? { options.min { $0.loan.totalPaid < $1.loan.totalPaid }?.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("GRASP").font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(3)
                Spacer()
                Text(date.formatted(date: .long, time: .shortened)).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Your car loan, decided").font(.system(size: 26, weight: .bold))
                Text("Every number here was read off your paperwork and worked out by Grasp, not guessed by an AI.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            section("The options") {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        ForEach(["", "APR", "Months", "Monthly", "Total paid", "Interest"], id: \.self) { title in
                            Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(options) { option in
                        GridRow {
                            Text(option.name).fontWeight(option.name == best ? .bold : .regular)
                            Text(option.loan.apr.formatted(.percent.precision(.fractionLength(1))))
                            Text("\(option.loan.termMonths)")
                            Text(money(option.loan.monthlyPayment, cents: true))
                            Text(money(option.loan.totalPaid)).fontWeight(.semibold)
                            Text(money(option.loan.totalInterest)).foregroundStyle(red)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(option.name == best ? green : .primary)
                    }
                }
                if let saved = facts.savedByQuote ?? (facts.savedByTerm > 0 ? facts.savedByTerm : nil) {
                    Text("Best option: \(best ?? "") saves \(money(saved)) against the offer as written.")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(green)
                }
            }

            if !facts.addOns.isEmpty || !facts.negotiableFees.isEmpty {
                section("Extras to refuse · \(money(facts.addOnTotal))") {
                    ForEach(facts.addOns, id: \.name) { addOn in
                        row(addOn.name, money(addOn.amount), note: [addOn.onContract ? "on the contract" : nil, addOn.onSticker ? "on the window sticker" : nil].compactMap { $0 }.joined(separator: " and "))
                    }
                    ForEach(facts.negotiableFees, id: \.name) { fee in
                        row(fee.name, money(fee.amount), note: "not optional, but ask them to lower it")
                    }
                }
            }

            section("What to say") {
                ForEach(Array(whatToSay.enumerated()), id: \.offset) { number, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(number + 1).").font(.system(size: 12, weight: .bold)).foregroundStyle(green)
                        Text(line).font(.system(size: 12))
                    }
                }
            }

            if !facts.pitchChecks.isEmpty {
                section("What the salesperson said") {
                    ForEach(facts.pitchChecks) { check in
                        row("“\(check.heard)”", "", note: check.note)
                    }
                }
            }

            Spacer()
            Text("Sources: the contract, window sticker and lender quote as photographed and read by Gemini; payments from the standard loan formula M = P·r / (1 − (1 + r)^−n). A sample decision aid, not financial advice.")
                .font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .padding(44)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ name: String, _ value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(name).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(value).font(.system(size: 12, weight: .semibold)).foregroundStyle(red)
            }
            Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func money(_ value: Double, cents: Bool = false) -> String {
        dollars(value, cents: cents)
    }
}
