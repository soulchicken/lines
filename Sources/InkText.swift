import AppKit

struct InkText: InkMark {
    static let font = NSFont.systemFont(ofSize: 22, weight: .semibold)
    static let padding = CGSize(width: 10, height: 7)

    private(set) var bounds: CGRect
    private let content: NSAttributedString
    private var textFrame: CGRect
    private static let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    init?(text: String, color: PenColor, frame: CGRect, canvasBounds: CGRect) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let content = NSAttributedString(string: text, attributes: [
            .font: Self.font, .foregroundColor: color.ink, .paragraphStyle: style
        ])
        let textWidth = frame.width - 2 * Self.padding.width
        let measured = content.boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                                            options: Self.options)
        let height = min(ceil(measured.height) + 2 * Self.padding.height, canvasBounds.height - 16)
        let bottom = max(canvasBounds.minY + 8, frame.maxY - height)
        bounds = CGRect(x: frame.minX, y: bottom, width: min(frame.width, ceil(measured.width) + 2 * Self.padding.width),
                        height: height)
        textFrame = CGRect(x: frame.minX + Self.padding.width, y: bottom + Self.padding.height,
                           width: textWidth, height: height - 2 * Self.padding.height)
        self.content = content
    }

    func moved(dx: CGFloat, dy: CGFloat, within canvas: CGRect) -> InkText {
        let x = min(max(canvas.minX, bounds.minX + dx), canvas.maxX - bounds.width)
        let y = min(max(canvas.minY, bounds.minY + dy), canvas.maxY - bounds.height)
        var moved = self
        moved.bounds.origin = CGPoint(x: x, y: y)
        moved.textFrame = textFrame.offsetBy(dx: x - bounds.minX, dy: y - bounds.minY)
        return moved
    }

    func draw(in context: CGContext, dirtyRect: CGRect) {
        guard bounds.intersects(dirtyRect) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        content.draw(with: textFrame, options: Self.options)
        NSGraphicsContext.restoreGraphicsState()
    }
}
