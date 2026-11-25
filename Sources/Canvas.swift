import AppKit

// A separately backed transparent view lets the compositor retain finished ink
// while only the pointer's current stroke is changing.
private final class LiveInkView: NSView {
    var stroke: InkStroke?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        stroke?.draw(in: context, dirtyRect: dirtyRect)
    }
}

final class InkCanvas: NSView {
    enum Tool {
        case pen, rectangle, text, laser
    }

    private enum Edit {
        case addMark
        case clear([InkMark])
        case moveText(index: Int, previous: InkText)
    }

    private struct TextDrag {
        let index: Int
        let original: InkText
        let start: CGPoint
    }

    private let palette: PenPalette
    private var marks: [InkMark] = []
    private var history: [Edit] = []
    private let live = LiveInkView()
    private let laser = LaserPointerView()
    private var textDraft: (scroll: NSScrollView, editor: NSTextView, color: PenColor)?
    private var textDrag: TextDrag?
    var textEditor: NSTextView? { textDraft?.editor }
    private(set) var tool: Tool = .pen
    var isLaserActive: Bool { tool == .laser }
    var onToolChange: (() -> Void)?
    let toolbar: InkToolbar

    init(palette: PenPalette) {
        self.palette = palette
        toolbar = InkToolbar(palette: palette)
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        laser.isHidden = true
        for overlay in [live as NSView, laser] {
            overlay.frame = bounds
            overlay.autoresizingMask = [.width, .height]
            overlay.wantsLayer = true
            overlay.layerContentsRedrawPolicy = .onSetNeedsDisplay
            addSubview(overlay)
        }
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.onSelectTool = { [weak self] in self?.selectTool($0) }
        addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.centerXAnchor.constraint(equalTo: centerXAnchor),
            toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 52)
        ])
        menu = palette.makeMenu()
    }

    required init?(coder: NSCoder) { nil }

    func toggleLaser() {
        selectTool(isLaserActive ? .pen : .laser)
    }

    private func selectTool(_ tool: Tool) {
        guard self.tool != tool else { return }
        commitText()
        finishTextDrag()
        finishLiveInk()
        self.tool = tool
        laser.clear()
        laser.isHidden = !isLaserActive
        window?.acceptsMouseMovedEvents = isLaserActive
        if isLaserActive, let window {
            displayLaser(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
        window?.invalidateCursorRects(for: self)
        onToolChange?()
    }

    func moveLaser(with event: NSEvent) {
        displayLaser(at: convert(event.locationInWindow, from: nil))
    }

    func clearLaserTrail() { laser.clear() }

    private func displayLaser(at point: CGPoint) {
        if toolbar.frame.contains(point) { laser.clear() } else { laser.point(at: point) }
    }

    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: tool == .text ? .iBeam : .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        if isLaserActive { moveLaser(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        if tool == .text {
            finishTextDrag()
            if textDraft != nil {
                commitText()
            } else if let index = marks.indices.reversed().first(where: {
                marks[$0] is InkText && marks[$0].bounds.contains(point)
            }), let text = marks[index] as? InkText {
                textDrag = TextDrag(index: index, original: text, start: point)
            } else {
                beginText(at: point)
            }
            return
        }
        let stroke = InkStroke(start: point, color: palette.selected, isRectangle: tool == .rectangle)
        if tool == .pen { record(stroke) }
        live.stroke = stroke
        live.setNeedsDisplay(stroke.tipBounds)
    }

    override func mouseDragged(with event: NSEvent) {
        if isLaserActive { moveLaser(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        if let drag = textDrag {
            let previous = marks[drag.index].bounds
            let moved = drag.original.moved(dx: point.x - drag.start.x, dy: point.y - drag.start.y, within: bounds)
            if previous != moved.bounds {
                marks[drag.index] = moved
                setNeedsDisplay(previous.insetBy(dx: -1, dy: -1))
                setNeedsDisplay(moved.bounds.insetBy(dx: -1, dy: -1))
            }
            return
        }
        if let dirty = live.stroke?.append(point) { live.setNeedsDisplay(dirty) }
    }

    override func mouseUp(with event: NSEvent) {
        if isLaserActive { moveLaser(with: event); return }
        mouseDragged(with: event)
        finishTextDrag()
        finishLiveInk()
    }

    private func finishTextDrag() {
        guard let drag = textDrag else { return }
        textDrag = nil
        if marks[drag.index].bounds.origin != drag.original.bounds.origin {
            history.append(.moveText(index: drag.index, previous: drag.original))
        }
    }

    private func record(_ mark: InkMark) {
        marks.append(mark)
        history.append(.addMark)
    }

    private func beginText(at point: CGPoint) {
        let size = CGSize(width: min(340, bounds.width - 16), height: min(104, bounds.height - 16))
        guard size.width > 20, size.height > 20 else { return }
        let frame = CGRect(x: min(max(point.x, bounds.minX + 8), bounds.maxX - size.width - 8),
                           y: min(max(point.y - size.height, bounds.minY + 8), bounds.maxY - size.height - 8),
                           width: size.width, height: size.height)
        let scroll = NSTextView.scrollableTextView()
        guard let editor = scroll.documentView as? NSTextView else { return }
        scroll.frame = frame
        scroll.borderType = .lineBorder
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.font = InkText.font
        editor.drawsBackground = false
        let color = palette.selected
        editor.textColor = color.ink
        editor.insertionPointColor = color.ink
        editor.textContainerInset = InkText.padding
        editor.textContainer?.lineFragmentPadding = 0
        editor.setAccessibilityLabel("화면에 넣을 텍스트")
        addSubview(scroll, positioned: .below, relativeTo: toolbar)
        textDraft = (scroll, editor, color)
        window?.makeFirstResponder(editor)
    }

    func commitText() {
        guard let draft = textDraft else { return }
        draft.editor.unmarkText()
        if let mark = InkText(text: draft.editor.string, color: draft.color,
                              frame: draft.scroll.frame, canvasBounds: bounds) {
            record(mark)
            setNeedsDisplay(mark.bounds.insetBy(dx: -1, dy: -1))
        }
        cancelText()
    }

    func cancelText() {
        guard let draft = textDraft else { return }
        textDraft = nil
        window?.makeFirstResponder(self)
        draft.scroll.removeFromSuperview()
    }

    private func finishLiveInk() {
        guard let stroke = live.stroke else { return }
        if tool == .rectangle && stroke.hasInk { record(stroke) }
        setNeedsDisplay(stroke.bounds)
        discardLiveInk()
    }

    private func discardLiveInk() {
        if let dirty = live.stroke?.bounds { live.setNeedsDisplay(dirty) }
        live.stroke = nil
    }

    func snapshotInk(scale: CGFloat) throws -> CGImage? {
        let rectangle = tool == .rectangle ? live.stroke : nil
        guard !marks.isEmpty || rectangle?.hasInk == true else { return nil }
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CaptureError.imageUnavailable }
        context.scaleBy(x: scale, y: scale)
        for mark in marks { mark.draw(in: context, dirtyRect: bounds) }
        rectangle?.draw(in: context, dirtyRect: bounds)
        guard let ink = context.makeImage() else { throw CaptureError.imageUnavailable }
        return ink
    }

    func undoLastEdit() {
        if textDraft != nil { cancelText(); return }
        finishTextDrag()
        if tool == .rectangle, let rectangle = live.stroke {
            discardLiveInk()
            if rectangle.hasInk { return }
        }
        guard let edit = history.popLast() else { return }
        discardLiveInk()
        switch edit {
        case .addMark: marks.removeLast()
        case .clear(let previous): marks = previous
        case .moveText(let index, let previous): marks[index] = previous
        }
        needsDisplay = true
    }

    func clear() {
        cancelText()
        finishTextDrag()
        discardLiveInk()
        guard !marks.isEmpty else { return }
        history.append(.clear(marks))
        marks.removeAll()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // A fully transparent area of a macOS window can pass clicks through.
        NSColor.black.withAlphaComponent(0.01).setFill()
        dirtyRect.fill(using: .copy)
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            for mark in marks {
                if let stroke = mark as? InkStroke, stroke === live.stroke { continue }
                mark.draw(in: context, dirtyRect: dirtyRect)
            }
            context.restoreGState()
        }
    }
}

final class InkPanel: NSPanel {
    let canvas: InkCanvas
    private let palette: PenPalette
    var onToggleLaser: (() -> Void)?
    var onCapture: (() -> Void)?
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
        canvas.toolbar.onAction = { [weak self] in self?.perform($0) }
        isReleasedWhenClosed = false
    }

    private var previousCoalescing: Bool?

    override func becomeKey() {
        super.becomeKey()
        if previousCoalescing == nil {
            previousCoalescing = NSEvent.isMouseCoalescingEnabled
            NSEvent.isMouseCoalescingEnabled = false
        }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .mouseMoved && canvas.isLaserActive {
            canvas.moveLaser(with: event)
            // Allow AppKit to update button hover states and tooltips.
        }
        super.sendEvent(event)
    }

    override func resignKey() {
        canvas.clearLaserTrail()
        if let previousCoalescing {
            NSEvent.isMouseCoalescingEnabled = previousCoalescing
            self.previousCoalescing = nil
        }
        super.resignKey()
    }

    func perform(_ action: ShortcutAction) {
        switch action {
        case .toggle, .finish: onFinish?()
        case .capture: onCapture?()
        case .laser: onToggleLaser?()
        case .undo: canvas.undoLastEdit()
        case .clear: canvas.clear()
        case .red: palette.select(.red)
        case .blue: palette.select(.blue)
        case .green: palette.select(.green)
        case .yellow: palette.select(.yellow)
        }
    }
}
