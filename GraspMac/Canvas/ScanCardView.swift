import GraspKit
import SwiftUI

/// A photo from the phone while Gemini reads it, and what was found if it doesn't become a chart.
struct ScanCardView: View {
    let scan: Scan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(nsImage: scan.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: Card.photoHeight(scan.image))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(scan.status == .reading ? 0.7 : 1)

            switch scan.status {
            case .reading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the paper…")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
            case .read(let reading):
                found(reading)
            case .failed(let message):
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.warn)
                    .lineLimit(3)
            }
        }
    }

    @ViewBuilder
    private func found(_ reading: OfferReading) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title(reading.documentType))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
            if reading.addOns.isEmpty {
                Text(reading.documentType == .other ? "Nothing to chart on this page." : "No add-ons found.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            } else {
                Text("ADD-ONS · \(dollars(reading.addOnTotal))")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.warn)
                ForEach(reading.addOns, id: \.name) { fee in
                    HStack {
                        Text(fee.name)
                        Spacer()
                        Text(dollars(fee.amount)).font(.system(size: 12, design: .monospaced))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.warn)
                }
            }
        }
    }

    private func title(_ type: OfferReading.DocumentType) -> String {
        switch type {
        case .loanContract: "Loan contract"
        case .windowSticker: "Window sticker"
        case .loanQuote: "Loan quote"
        case .other: "Not a car offer"
        }
    }
}
