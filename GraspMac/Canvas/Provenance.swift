import AppKit
import GraspKit
import SwiftUI

/// Anything on the canvas you can hover to see where it came from.
enum HoverTarget: Hashable {
    /// A number read off a page.
    case fact(document: UUID, key: String)
    /// A catch in a page's fine print.
    case catchItem(document: UUID, title: String)
    /// A number Grasp worked out, shown on a card.
    case derived(card: UUID, name: String)
    /// Words on a page that back an answer.
    case answerSource(card: UUID, index: Int)
    /// The passage of a paper a note (index below the note count) or a direction (after them) is about.
    case passage(card: UUID, index: Int)
    /// A step in a lab notebook: the frame, the words and the reading at that moment.
    case labStep(card: UUID, index: Int)
    /// Words on a page that a card cites (a paper's equation, a protocol step, a bill line).
    case cited(card: UUID, index: Int)
    /// A published paper on a related-work card.
    case work(card: UUID, index: Int)
}

/// Words on a page a card cites, with what they back up.
struct Citation {
    var documentID: UUID
    var cited: Cited
    var heading: String
    var detail: String?
}

/// Where something came from, ready to show.
struct Provenance {
    struct Input: Identifiable {
        var label: String
        var value: String
        /// Where this input came from, in a few words.
        var source: String
        var id: String { label }
    }

    var heading: String
    /// "Read from … at 8:21 PM" or "Worked out by Grasp".
    var origin: String
    /// The words on the page.
    var quote: String?
    var formula: String?
    /// A band of the photo around the words, and where the words sit in it (normalized).
    var crop: NSImage?
    var highlight: CGRect?
    var inputs: [Input] = []
}

/// A band of a page photo around a box, with the box's place inside it.
enum PageCrop {
    static func around(_ box: CGRect, in image: NSImage) -> (image: NSImage, highlight: CGRect)? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = Double(cgImage.width), height = Double(cgImage.height)
        // Enough of the page around it to read the line: the words, the line above and below,
        // and a good stretch either side.
        let padX = max(box.width * 0.8, 0.2)
        let padY = max(box.height * 2, 0.035)
        let region = CGRect(x: box.minX - padX, y: box.minY - padY, width: box.width + padX * 2, height: box.height + padY * 2)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !region.isNull, region.width > 0, region.height > 0,
              let cropped = cgImage.cropping(to: CGRect(x: region.minX * width, y: region.minY * height,
                                                       width: region.width * width, height: region.height * height).integral)
        else { return nil }
        let highlight = CGRect(
            x: (box.minX - region.minX) / region.width,
            y: (box.minY - region.minY) / region.height,
            width: box.width / region.width,
            height: box.height / region.height
        )
        return (NSImage(cgImage: cropped, size: .zero), highlight)
    }
}

extension View {
    /// Hover this (mouse, or an open hand held still over it) to see where it came from.
    func hoverSource(_ target: HoverTarget) -> some View {
        modifier(HoverSource(target: target))
    }
}

private struct HoverSource: ViewModifier {
    let target: HoverTarget
    @Environment(CanvasModel.self) private var canvas

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(canvas.hovered == target ? Theme.hot.opacity(0.22) : .clear)
            )
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("canvas"))   // CanvasModel.space
            } action: { frame in
                canvas.setHoverFrame(target, frame)
            }
            .onHover { inside in canvas.mouseHover(target, inside: inside) }
            .onDisappear { canvas.removeHoverFrame(target) }
    }
}

/// The card that pops up next to whatever is hovered: the photo with the words lit, or the
/// formula and where each of its inputs came from.
struct ProvenancePopover: View {
    let provenance: Provenance

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("WHERE THIS COMES FROM")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.muted)
            Text(provenance.heading)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.ink)

            if let crop = provenance.crop {
                Image(nsImage: crop)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 372, maxHeight: 130)
                    .overlay {
                        GeometryReader { geometry in
                            if let box = provenance.highlight {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.hot.opacity(0.25))
                                    .stroke(Theme.hot, lineWidth: 2.5)
                                    .frame(width: box.width * geometry.size.width + 8, height: box.height * geometry.size.height + 6)
                                    .position(x: box.midX * geometry.size.width, y: box.midY * geometry.size.height)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if let quote = provenance.quote {
                Text("“\(quote)”")
                    .font(.system(size: 13).italic())
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let formula = provenance.formula {
                Text(formula)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(provenance.inputs) { input in
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(input.label).foregroundStyle(Theme.muted)
                        Spacer()
                        Text(input.value).fontWeight(.semibold).foregroundStyle(Theme.ink)
                    }
                    .font(.system(size: 13))
                    Text(input.source)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(2)
                }
            }
            Text(provenance.origin)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
        }
        .padding(14)
        .frame(width: 400, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hot, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        .allowsHitTesting(false)
    }
}
