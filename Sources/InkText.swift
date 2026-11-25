import AppKit

struct InkText: InkMark {
    struct Style: Equatable {
        enum Weight: String, CaseIterable {
            case regular, semibold, bold

            var title: String {
                switch self {
                case .regular: return "보통"
                case .semibold: return "약간 굵게"
                case .bold: return "굵게"
                }
            }

            var fontWeight: NSFont.Weight {
                switch self {
                case .regular: return .regular
                case .semibold: return .semibold
                case .bold: return .bold
                }
            }
        }

        var color: PenColor
        var size = 22
        var weight: Weight = .semibold
        var italic = false

        var attributes: [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            return [.font: NSFont.systemFont(ofSize: CGFloat(size), weight: weight.fontWeight),
                    .foregroundColor: color.ink, .paragraphStyle: paragraph, .obliqueness: italic ? 0.2 : 0]
        }
    }

    static let padding = CGSize(width: 10, height: 7)

    private(set) var bounds: CGRect
    let style: Style
    private let content: NSAttributedString
    private var textFrame: CGRect
    private static let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    init?(text: String, style: Style, frame: CGRect, canvasBounds: CGRect) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.style = style
        let content = NSAttributedString(string: text, attributes: style.attributes)
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

    func restyled(_ style: Style, within canvas: CGRect) -> InkText? {
        let frame = CGRect(x: bounds.minX, y: bounds.minY,
                           width: textFrame.width + 2 * Self.padding.width, height: bounds.height)
        return InkText(text: content.string, style: style, frame: frame, canvasBounds: canvas)?
            .moved(dx: 0, dy: 0, within: canvas)
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
