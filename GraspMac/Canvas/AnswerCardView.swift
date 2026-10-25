import GraspKit
import SwiftUI

/// A question answered from the pages: the answer, whether its numbers checked out, the words
/// on the pages that back it (hover each to see it on the photo), and the math Swift did.
struct AnswerCardView: View {
    let cardID: UUID
    let card: AnswerCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("YOU ASKED")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text("“\(card.question)”")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                if let followsOn = card.followsOn {
                    Text("after “\(followsOn)”")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }

            Text(card.answer.answer)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Label(card.answer.numbersChecked ? "Every number checked against the pages and Grasp's math" : "Some numbers couldn't be traced: check them",
                  systemImage: card.answer.numbersChecked ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(card.answer.numbersChecked ? Theme.accent : Theme.hot)

            if !card.sources.isEmpty {
                Text("WHERE IT SAYS SO")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                ForEach(Array(card.sources.enumerated()), id: \.offset) { index, source in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("“\(source.quote)”")
                            .font(.system(size: 13).italic())
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text(source.documentTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(height: 34, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hoverSource(.answerSource(card: cardID, index: index))
                }
            }

            if !card.answer.calculations.isEmpty {
                Text("GRASP'S MATH")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                ForEach(card.answer.calculations, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
