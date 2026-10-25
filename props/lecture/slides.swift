// Renders the lecture's slides to slide1.png … slide5.png. Run by make-lecture.sh.
import AppKit

let slides: [(title: String, body: String)] = [
    ("Newton's Law of Cooling", "Physics 101 · Lecture 7"),
    ("T(t) = T_room + (T₀ − T_room) · e^(−k·t)", "k sets the pace · open paper cup: k ≈ 0.031 per minute"),
    ("Half-life of the difference", "t½ = ln 2 / k ≈ 22 minutes for an open cup"),
    ("A lid slows cooling", "less evaporation · k ≈ 0.019 per minute"),
    ("Try it", "three cups at 90 °C · open, lid, ice · log every second · fit k"),
]

let size = NSSize(width: 1280, height: 720)
for (index, slide) in slides.enumerated() {
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.11, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    NSColor(calibratedRed: 0.22, green: 0.76, blue: 0.66, alpha: 1).setFill()
    NSRect(x: 90, y: 470, width: 120, height: 8).fill()
    let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 58, weight: .bold), .foregroundColor: NSColor.white]
    let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 34, weight: .regular),
                                               .foregroundColor: NSColor(white: 0.8, alpha: 1)]
    (slide.title as NSString).draw(in: NSRect(x: 90, y: 300, width: 1100, height: 150), withAttributes: title)
    (slide.body as NSString).draw(in: NSRect(x: 90, y: 180, width: 1100, height: 110), withAttributes: body)
    ("Slide \(index + 1)" as NSString).draw(at: NSPoint(x: 90, y: 60), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 20, weight: .regular),
                                                                                   .foregroundColor: NSColor(white: 0.5, alpha: 1)])
    image.unlockFocus()
    let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "slide\(index + 1).png"))
}
