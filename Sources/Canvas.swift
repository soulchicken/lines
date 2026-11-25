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

final class InkCanvas: NSView, NSTextViewDelegate {
    enum Tool {
        case pen, line, rectangle, text, laser
    }

    private enum Edit {
        case addMark
        case clear([InkMark])
        case replaceText(index: Int, previous: InkText)
        case restyleStroke(InkStroke, previous: InkStroke.Style)
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
    private var textDraft: (scroll: NSScrollView, editor: NSTextView, style: InkText.Style)?
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
        toolbar.makeColorMenu = { [weak self] in self?.toolColorMenu(for: $0) }
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

    func selectTool(_ tool: Tool) {
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

    private var widthPreferenceKey: String {
        switch tool {
        case .line: return "lineWidth"
        case .rectangle: return "rectangleWidth"
        default: return "penWidth"
        }
    }

    private var strokeWidth: Int {
        let saved = UserDefaults.standard.integer(forKey: widthPreferenceKey)
        return InkStyleMenu.widths.contains(saved) ? saved : 4
    }

    private var defaultTextStyle: InkText.Style {
        let defaults = UserDefaults.standard
        let size = defaults.integer(forKey: "annotationTextSize")
        let weight = defaults.string(forKey: "annotationTextWeight").flatMap(InkText.Style.Weight.init(rawValue:))
        return InkText.Style(color: palette.selected, size: InkStyleMenu.fontSizes.contains(size) ? size : 22,
                             weight: weight ?? .semibold, italic: defaults.bool(forKey: "annotationTextItalic"))
    }

    private func markIndex(at point: CGPoint) -> Int? {
        marks.indices.reversed().first { index in
            let mark = marks[index]
            if let stroke = mark as? InkStroke { return stroke.contains(point) }
            return mark.bounds.contains(point)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = annotationMenu(at: convert(event.locationInWindow, from: nil))
        guard isLaserActive else { return menu }
        let laserMenu = menu ?? NSMenu()
        if !laserMenu.items.isEmpty { laserMenu.addItem(.separator()) }
        InkStyleMenu.addLaserDuration(to: laserMenu, selected: laser.duration) { [weak self] duration in
            self?.laser.duration = duration
        }
        return laserMenu
    }

    private func annotationMenu(at point: CGPoint) -> NSMenu? {
        if let index = markIndex(at: point) {
            if let text = marks[index] as? InkText {
                return InkStyleMenu.text(text.style) { [weak self] style in
                    self?.restyleText(at: index, to: style)
                }
            }
            if let stroke = marks[index] as? InkStroke {
                return InkStyleMenu.stroke(stroke.style) { [weak self, weak stroke] style in
                    if let stroke { self?.restyleStroke(stroke, to: style) }
                }
            }
        }
        if tool == .text {
            return InkStyleMenu.text(defaultTextStyle) { [weak self] style in
                self?.storeTextStyle(style)
            }
        }
        if tool == .laser { return nil }
        let key = widthPreferenceKey
        return InkStyleMenu.stroke(InkStroke.Style(color: palette.selected, width: strokeWidth)) { [weak self] style in
            UserDefaults.standard.set(style.width, forKey: key)
            self?.palette.select(style.color)
        }
    }

    private func toolColorMenu(for tool: Tool) -> NSMenu {
        switch tool {
        case .pen, .line, .rectangle:
            return palette.makeMenu()
        case .text:
            return InkStyleMenu.colors(selected: textDraft?.style.color ?? palette.selected) { [weak self] color in
                guard let self else { return }
                if let draft = self.textDraft {
                    var style = draft.style
                    style.color = color
                    self.textDraft?.style = style
                    self.applyTextStyle(style, to: draft.editor)
                }
                self.palette.select(color)
            }
        case .laser:
            return InkStyleMenu.colors(selected: laser.color) { [weak self] color in
                self?.laser.color = color
            }
        }
    }

    private func restyleStroke(_ stroke: InkStroke, to style: InkStroke.Style) {
        guard stroke.style != style else { return }
        finishLiveInk()
        history.append(.restyleStroke(stroke, previous: stroke.style))
        stroke.style = style
        setNeedsDisplay(stroke.bounds)
    }

    private func restyleText(at index: Int, to style: InkText.Style) {
        guard marks.indices.contains(index), let original = marks[index] as? InkText,
              original.style != style, let updated = original.restyled(style, within: bounds) else { return }
        finishTextDrag()
        history.append(.replaceText(index: index, previous: original))
        marks[index] = updated
        setNeedsDisplay(original.bounds.union(updated.bounds).insetBy(dx: -1, dy: -1))
    }

    private func storeTextStyle(_ style: InkText.Style) {
        let defaults = UserDefaults.standard
        defaults.set(style.size, forKey: "annotationTextSize")
        defaults.set(style.weight.rawValue, forKey: "annotationTextWeight")
        defaults.set(style.italic, forKey: "annotationTextItalic")
        palette.select(style.color)
    }

    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        guard let draft = textDraft, draft.editor === view else { return menu }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        return InkStyleMenu.text(draft.style, in: menu) { [weak self, weak view] style in
            guard let self, let view, self.textDraft?.editor === view else { return }
            self.textDraft?.style = style
            self.applyTextStyle(style, to: view)
        }
    }

    private func applyTextStyle(_ style: InkText.Style, to editor: NSTextView) {
        editor.unmarkText()
        let attributes = style.attributes
        if let storage = editor.textStorage, storage.length > 0 {
            storage.addAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
        editor.typingAttributes = attributes
        editor.insertionPointColor = style.color.ink
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
        let shape: InkStroke.Shape
        switch tool {
        case .line: shape = .line
        case .rectangle: shape = .rectangle
        default: shape = .freehand
        }
        let stroke = InkStroke(start: point, color: palette.selected, shape: shape, width: strokeWidth)
        if shape == .freehand { record(stroke) }
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
        if let dirty = live.stroke?.append(point, arrow: event.modifierFlags.contains(.option)) {
            live.setNeedsDisplay(dirty)
        }
    }

    func updateArrowPreview(_ modifiers: NSEvent.ModifierFlags) {
        if let dirty = live.stroke?.updateArrow(modifiers.contains(.option)) { live.setNeedsDisplay(dirty) }
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
            history.append(.replaceText(index: drag.index, previous: drag.original))
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
        editor.drawsBackground = false
        editor.delegate = self
        let style = defaultTextStyle
        applyTextStyle(style, to: editor)
        editor.textContainerInset = InkText.padding
        editor.textContainer?.lineFragmentPadding = 0
        editor.setAccessibilityLabel("화면에 넣을 텍스트")
        addSubview(scroll, positioned: .below, relativeTo: toolbar)
        textDraft = (scroll, editor, style)
        window?.makeFirstResponder(editor)
    }

    func commitText() {
        guard let draft = textDraft else { return }
        draft.editor.unmarkText()
        if let mark = InkText(text: draft.editor.string, style: draft.style,
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
        if stroke.shape != .freehand && stroke.hasInk { record(stroke) }
        setNeedsDisplay(stroke.bounds)
        discardLiveInk()
    }

    private func discardLiveInk() {
        if let dirty = live.stroke?.bounds { live.setNeedsDisplay(dirty) }
        live.stroke = nil
    }

    func snapshotInk(scale: CGFloat) throws -> CGImage? {
        let shape = live.stroke?.shape == .freehand ? nil : live.stroke
        guard !marks.isEmpty || shape?.hasInk == true else { return nil }
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CaptureError.imageUnavailable }
        context.scaleBy(x: scale, y: scale)
        for mark in marks { mark.draw(in: context, dirtyRect: bounds) }
        shape?.draw(in: context, dirtyRect: bounds)
        guard let ink = context.makeImage() else { throw CaptureError.imageUnavailable }
        return ink
    }

    func undoLastEdit() {
        if textDraft != nil { cancelText(); return }
        finishTextDrag()
        if let shape = live.stroke, shape.shape != .freehand {
            discardLiveInk()
            if shape.hasInk { return }
        }
        guard let edit = history.popLast() else { return }
        discardLiveInk()
        switch edit {
        case .addMark: marks.removeLast()
        case .clear(let previous): marks = previous
        case .replaceText(let index, let previous): marks[index] = previous
        case .restyleStroke(let stroke, let previous): stroke.style = previous
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
        if event.type == .flagsChanged && canvas.tool == .line {
            canvas.updateArrowPreview(event.modifierFlags)
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
        case .pen: canvas.selectTool(.pen)
        case .line: canvas.selectTool(.line)
        case .rectangle: canvas.selectTool(.rectangle)
        case .text: canvas.selectTool(.text)
        case .laser: canvas.selectTool(.laser)
        case .undo: canvas.undoLastEdit()
        case .clear: canvas.clear()
        case .red: palette.select(.red)
        case .blue: palette.select(.blue)
        case .green: palette.select(.green)
        case .yellow: palette.select(.yellow)
        }
    }
}
