import GraspKit
import SwiftUI

/// A dispute letter, ready to send: the total to get back, each problem with Swift's math (hover
/// for the line on the bill), what's worth asking about, and the letter itself.
struct LetterCardView: View {
    let cardID: UUID
    let card: LetterCard

    private var letter: DisputeLetter { card.letter }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("THE DISPUTE · READY TO SEND")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text("To \(letter.company)" + (letter.account.map { " · Account \($0)" } ?? ""))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dollars(letter.total, cents: true))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                Text("to get back on this bill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            }

            ForEach(Array(letter.items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(dollars(item.amount, cents: true))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.hot)
                    }
                    Text("\(item.math) · \(item.reason)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                .frame(height: 36, alignment: .topLeading)
                .hoverSource(.cited(card: cardID, index: index))
            }

            if !letter.questions.isEmpty {
                Text("ALSO ASKING WHY, NOT IN THE TOTAL")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .frame(height: 18, alignment: .bottomLeading)
                ForEach(Array(letter.questions.enumerated()), id: \.offset) { offset, item in
                    Text("\(item.title) · \(dollars(item.amount, cents: true))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .frame(height: 18, alignment: .leading)
                        .hoverSource(.cited(card: cardID, index: letter.items.count + offset))
                }
            }

            Text(letter.opening)
                .font(.system(size: 12).italic())
                .foregroundStyle(Theme.muted)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("\u{2318}\u{21E7}C copies the whole letter · signed \(letter.name ?? "with your name")")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
    }
}
