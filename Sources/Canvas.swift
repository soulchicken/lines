import AppKit
import Carbon.HIToolbox

final class InkCanvas: NSView {
    private struct Stroke {
        let path: NSBezierPath
        let color: PenColor
    }
    private enum Edit {
        case addStroke
        case clear([Stroke])
    }

    private let palette: PenPalette
    private var strokes: [Stroke] = []
    private var history: [Edit] = []
    private var currentStroke: NSBezierPath?
    private var showsHint = true

    init(palette: PenPalette) {
        self.palette = palette
        super.init(frame: .zero)
        menu = palette.makeMenu()
    }

    required init?(coder: NSCoder) { nil }

    func showColorHint() {
        showsHint = true
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: point)
        // A click without a drag also leaves a visible dot.
        path.line(to: CGPoint(x: point.x + 0.01, y: point.y))
        strokes.append(Stroke(path: path, color: palette.selected))
        history.append(.addStroke)
        currentStroke = path
        showsHint = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let path = currentStroke else { return }
        let from = path.currentPoint
        let to = convert(event.locationInWindow, from: nil)
        path.line(to: to)
        let segment = NSRect(x: min(from.x, to.x), y: min(from.y, to.y),
                             width: abs(to.x - from.x), height: abs(to.y - from.y))
        setNeedsDisplay(segment.insetBy(dx: -5, dy: -5))
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        currentStroke = nil
    }

    func undoLastEdit() {
        guard let edit = history.popLast() else { return }
        currentStroke = nil
        switch edit {
        case .addStroke: strokes.removeLast()
        case .clear(let previous): strokes = previous
        }
        needsDisplay = true
    }

    func clear() {
        guard !strokes.isEmpty else { return }
        history.append(.clear(strokes))
        strokes.removeAll()
        currentStroke = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // A fully transparent area of a macOS window can pass clicks through.
        NSColor.black.withAlphaComponent(0.01).setFill()
        dirtyRect.fill(using: .copy)
        for stroke in strokes where stroke.path.bounds.insetBy(dx: -5, dy: -5).intersects(dirtyRect) {
            let path = stroke.path
            NSColor.white.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 6
            path.stroke()
            stroke.color.ink.setStroke()
            path.lineWidth = 4
            path.stroke()
        }
        if showsHint {
            let hint = NSAttributedString(string: "\(palette.selected.name) 펜    ·    1–4 또는 우클릭으로 색 선택    ·    ⌘Z 취소    ·    Esc 종료",
                                          attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                                                       .foregroundColor: NSColor.white])
            let size = hint.size()
            let box = NSRect(x: (bounds.width - size.width) / 2 - 14, y: bounds.height - 88,
                             width: size.width + 28, height: size.height + 14)
            NSColor.black.withAlphaComponent(0.78).setFill()
            NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
            hint.draw(at: NSPoint(x: box.minX + 14, y: box.minY + 7))
        }
    }
}

final class InkPanel: NSPanel {
    let canvas: InkCanvas
    private let palette: PenPalette
    var onFinish: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(on screen: NSScreen, palette: PenPalette) {
        self.palette = palette
        canvas = InkCanvas(palette: palette)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        contentView = canvas
        isReleasedWhenClosed = false
    }

    func handleShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        let character = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command && (character == "z" || Int(event.keyCode) == kVK_ANSI_Z) {
            canvas.undoLastEdit()
            return true
        }
        guard modifiers.isEmpty else { return false }
        switch Int(event.keyCode) {
        case kVK_Escape: onFinish?()
        case kVK_Delete, kVK_ForwardDelete: canvas.clear()
        default:
            guard let character, let number = Int(character), let color = PenColor(rawValue: number)
            else { return false }
            palette.select(color)
        }
        return true
    }
}
