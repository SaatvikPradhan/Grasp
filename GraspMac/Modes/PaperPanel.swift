import GraspKit
import SwiftUI

/// What Gemini read off the paper: the terms, the add-ons, and anything that doesn't add up.
struct PaperPanel: View {
    let reader: PaperReader

    var body: some View {
        if reader.state != .idle {
            VStack(alignment: .leading, spacing: 8) {
                header
                switch reader.state {
                case .idle:
                    EmptyView()
                case .reading:
                    if let photo = reader.photo {
                        Image(nsImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 140)
                            .opacity(0.6)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                case .read(let reading, _):
                    details(reading)
                case .failed(let message):
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(12)
            .frame(width: 280, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("THE PAPER")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.muted)
            Spacer()
            switch reader.state {
            case .reading:
                ProgressView().controlSize(.small)
                Text("Reading…").font(.system(size: 12)).foregroundStyle(Theme.muted)
            case .read(_, let seconds):
                Text(String(format: "read in %.1f s", seconds))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func details(_ reading: OfferReading) -> some View {
        Text(title(reading.documentType))
            .font(.system(size: 15, weight: .semibold))

        VStack(spacing: 4) {
            if let value = reading.cashPrice { row("Cash price", dollars(value)) }
            if let value = reading.amountFinanced { row("Amount financed", dollars(value)) }
            if let value = reading.aprPercent { row("APR", String(format: "%.2f%%", value)) }
            if let value = reading.termMonths { row("Term", "\(value) months") }
            if let value = reading.monthlyPayment { row("Monthly payment", dollars(value, cents: true)) }
        }

        if !reading.addOns.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("ADD-ONS · \(dollars(reading.addOnTotal))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                ForEach(reading.addOns, id: \.name) { fee in
                    row(fee.name, dollars(fee.amount))
                }
            }
            .foregroundStyle(Theme.warn)
        }

        ForEach(reading.discrepancies, id: \.self) { problem in
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.hot)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).font(.system(size: 12, design: .monospaced))
        }
        .font(.system(size: 12))
    }

    private func title(_ type: OfferReading.DocumentType) -> String {
        switch type {
        case .loanContract: "Loan contract"
        case .windowSticker: "Window sticker"
        case .loanQuote: "Loan quote"
        case .other: "Not a car offer"
        }
    }

    private func dollars(_ value: Double, cents: Bool = false) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(cents ? 2 : 0)))
    }
}
