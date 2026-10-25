import Foundation

/// A page as the question answerer sees it.
public struct AskedDocument: Sendable {
    public var title: String
    public var kind: String
    public var summary: String
    public var facts: [String]
    public var catches: [String]
    /// Every word on the page.
    public var text: String

    public init(title: String, kind: String, summary: String, facts: [String], catches: [String], text: String) {
        self.title = title
        self.kind = kind
        self.summary = summary
        self.facts = facts
        self.catches = catches
        self.text = text
    }

    public init(_ reading: PageReading, text: [String]) {
        self.init(
            title: reading.title, kind: reading.kind, summary: reading.summary,
            facts: reading.facts.map { "\($0.label): \($0.asPrinted)" },
            catches: reading.catches.map { "\($0.title): \($0.explanation)" },
            text: text.joined(separator: "\n")
        )
    }
}

/// An answer, with the words on the page that back it and the math behind its numbers.
public struct GroundedAnswer: Equatable, Sendable {
    public var answer: String
    /// Shorter, for reading aloud.
    public var spoken: String
    /// Words copied from the pages that support the answer.
    public var quotes: [String]
    /// Each calculation Swift did for it: "loan_payment: $536.49 a month".
    public var calculations: [String]
    /// True when every number in the answer is on a page, came from a calculation, or was in the question.
    public var numbersChecked: Bool
}

/// Answers any question about the pages on the canvas. Gemini reads and explains; any arithmetic
/// goes through Swift tools, and every number in the answer is checked against the pages, the
/// calculations and the question.
public struct QuestionAnswerer: Sendable {
    public var client: GeminiClient

    public init(client: GeminiClient) {
        self.client = client
    }

    public func answer(_ question: String, documents: [AskedDocument], canvas: String) async throws -> GroundedAnswer {
        var contents: [[String: Any]] = [["role": "user", "parts": [["text": Self.prompt(question, documents: documents, canvas: canvas)]]]]
        var calculations: [String] = []
        var resultNumbers: [String] = []

        for _ in 0..<6 {
            let step = try await client.toolStep(contents, functions: Self.functions)
            contents.append(step.turn)
            if let final = step.calls.first(where: { $0.name == "give_answer" }) {
                let answer = final.text("answer") ?? ""
                let spoken = final.text("spoken") ?? answer
                let known = Self.known(question: question, documents: documents, canvas: canvas, results: resultNumbers)
                let used = Set(MoneyFacts.numbers(in: answer + " " + spoken))
                return GroundedAnswer(answer: answer, spoken: spoken, quotes: final.texts("quotes"),
                                      calculations: calculations, numbersChecked: used.isSubset(of: known))
            }
            guard !step.calls.isEmpty else { break }
            var responses: [[String: Any]] = []
            for call in step.calls {
                let result = Self.run(call)
                calculations.append("\(call.name): \(result.summary)")
                resultNumbers += result.values.map { Self.plain($0) }
                responses.append(["functionResponse": ["name": call.name, "response": result.response]])
            }
            contents.append(["role": "user", "parts": responses])
        }
        throw GeminiClient.Failure.noAnswer(reason: "no answer after several steps")
    }

    // MARK: Prompt

    static func prompt(_ question: String, documents: [AskedDocument], canvas: String) -> String {
        let pages = documents.isEmpty ? "No pages have been read yet." : documents.map { document in
            """
            ### \(document.title) (\(document.kind))
            \(document.summary)
            Key numbers: \(document.facts.joined(separator: "; "))
            Catches: \(document.catches.joined(separator: "; "))
            Full text:
            \(document.text.prefix(4_000))
            """
        }.joined(separator: "\n\n")
        return """
        You are Grasp. Answer the question using only the pages below and what's on the canvas.
        For any arithmetic at all, call a calculator tool; never work out a number yourself.
        When you're done, call give_answer: answer is one to three plain sentences; spoken is a shorter \
        version to read aloud; quotes are short phrases copied exactly from the pages that support the \
        answer. If the pages don't say, answer that they don't.

        On the canvas: \(canvas)

        \(pages)

        Question: \(question)
        """
    }

    // MARK: Tools

    static let functions: [[String: Any]] = [
        tool("loan_payment", "Monthly payment, total paid and interest for a fixed-rate loan.",
             ["principal": "NUMBER", "apr_percent": "NUMBER", "months": "NUMBER"]),
        tool("payoff_months", "How many months to pay off a balance (such as a credit card) at a fixed monthly payment, and the interest paid.",
             ["balance": "NUMBER", "apr_percent": "NUMBER", "monthly_payment": "NUMBER"]),
        tool("total_cost", "Total of a monthly price over some months plus one-time charges.",
             ["monthly": "NUMBER", "months": "NUMBER", "upfront": "NUMBER"]),
        tool("arithmetic", "Add, subtract, multiply or divide two numbers.",
             ["a": "NUMBER", "operation": "STRING", "b": "NUMBER"]),
        [
            "name": "give_answer",
            "description": "The final answer.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "answer": ["type": "STRING"],
                    "spoken": ["type": "STRING"],
                    "quotes": ["type": "ARRAY", "items": ["type": "STRING"]],
                ],
                "required": ["answer", "spoken", "quotes"],
            ],
        ],
    ]

    private static func tool(_ name: String, _ description: String, _ parameters: [String: String]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "parameters": [
                "type": "OBJECT",
                "properties": parameters.mapValues { ["type": $0] },
                "required": Array(parameters.keys),
            ],
        ]
    }

    /// Runs a calculator tool in Swift.
    static func run(_ call: FunctionCall) -> (response: [String: Any], summary: String, values: [Double]) {
        func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
        switch call.name {
        case "loan_payment":
            guard let principal = call.number("principal"), let apr = call.number("apr_percent"), let months = call.number("months"), months > 0 else { break }
            let loan = LoanTerms(principal: principal, apr: apr / 100, termMonths: Int(months.rounded()))
            // Totals the way a contract does: the rounded payment times the months.
            let monthly = round2(loan.monthlyPayment)
            let total = round2(monthly * Double(loan.termMonths)), interest = round2(total - principal)
            return (["monthly_payment": monthly, "total_paid": total, "interest": interest],
                    "\(money(monthly)) a month, \(money(total)) in total, \(money(interest)) interest", [monthly, total, interest])
        case "payoff_months":
            guard let balance = call.number("balance"), let apr = call.number("apr_percent"), let payment = call.number("monthly_payment") else { break }
            let rate = apr / 100 / 12
            var remaining = balance, months = 0, interest = 0.0
            while remaining > 0.005, months < 600 {
                let charge = remaining * rate
                guard payment > charge else {
                    return (["months": -1, "note": "The payment never covers the interest; the balance never shrinks."],
                            "never paid off at that payment", [])
                }
                interest += charge
                remaining = remaining + charge - payment
                months += 1
            }
            return (["months": months, "total_interest": round2(interest)],
                    "\(months) months, \(money(round2(interest))) interest", [Double(months), round2(interest)])
        case "total_cost":
            guard let monthly = call.number("monthly"), let months = call.number("months") else { break }
            let total = round2(monthly * months + (call.number("upfront") ?? 0))
            return (["total": total], "\(money(total)) in total", [total])
        case "arithmetic":
            guard let a = call.number("a"), let b = call.number("b") else { break }
            let operation = (call.text("operation") ?? "").lowercased()
            let result: Double? = switch operation {
            case "add", "+", "plus": a + b
            case "subtract", "-", "minus": a - b
            case "multiply", "*", "×", "times": a * b
            case "divide", "/", "÷": b == 0 ? nil : a / b
            default: nil
            }
            guard let result else { break }
            let rounded = round2(result)
            return (["result": rounded], "\(plain(a)) \(operation) \(plain(b)) = \(plain(rounded))", [rounded])
        default:
            break
        }
        return (["error": "Missing or invalid inputs."], "couldn't run", [])
    }

    // MARK: Checking numbers

    /// Numbers the answer may use: on the pages, on the canvas, in the question, or from a calculation,
    /// each also as whole dollars, since answers round.
    static func known(question: String, documents: [AskedDocument], canvas: String, results: [String]) -> Set<String> {
        let texts = [question, canvas] + documents.flatMap { [$0.text, $0.summary] + $0.facts + $0.catches }
        var numbers = Set(texts.flatMap(MoneyFacts.numbers) + results)
        for number in numbers {
            if let value = Double(number) {
                numbers.insert(String(Int(value.rounded())))
                numbers.insert(String(Int(value)))
            }
        }
        return numbers
    }

    private static func plain(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    private static func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }
}
