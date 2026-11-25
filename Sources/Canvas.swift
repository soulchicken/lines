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
    private enum Edit {
        case addStroke
        case clear([InkStroke])
    }

    private let palette: PenPalette
    private var strokes: [InkStroke] = []
    private var history: [Edit] = []
    private let live = LiveInkView()
    private let laser = LaserPointerView()
    var isLaserActive: Bool { !laser.isHidden }
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
        addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.centerXAnchor.constraint(equalTo: centerXAnchor),
            toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 52)
        ])
        menu = palette.makeMenu()
    }

    required init?(coder: NSCoder) { nil }

    func toggleLaser() {
        // Commit any in-progress pen stroke before switching tools.
        if let dirty = live.stroke?.bounds { setNeedsDisplay(dirty) }
        discardLiveInk()
        laser.clear()
        laser.isHidden.toggle()
        window?.acceptsMouseMovedEvents = isLaserActive
        if isLaserActive, let window {
            displayLaser(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
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
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        if isLaserActive { moveLaser(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        let stroke = InkStroke(start: point, color: palette.selected)
        strokes.append(stroke)
        history.append(.addStroke)
        live.stroke = stroke
        live.setNeedsDisplay(stroke.tipBounds)
    }

    override func mouseDragged(with event: NSEvent) {
        if isLaserActive { moveLaser(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        if let dirty = live.stroke?.append(point) { live.setNeedsDisplay(dirty) }
    }

    override func mouseUp(with event: NSEvent) {
        if isLaserActive { moveLaser(with: event); return }
        mouseDragged(with: event)
        if let dirty = live.stroke?.bounds { setNeedsDisplay(dirty) }
        discardLiveInk()
    }

    private func discardLiveInk() {
        if let dirty = live.stroke?.bounds { live.setNeedsDisplay(dirty) }
        live.stroke = nil
    }

    func snapshotInk(scale: CGFloat) throws -> CGImage? {
        guard !strokes.isEmpty else { return nil }
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CaptureError.imageUnavailable }
        context.scaleBy(x: scale, y: scale)
        for stroke in strokes { stroke.draw(in: context, dirtyRect: bounds) }
        guard let ink = context.makeImage() else { throw CaptureError.imageUnavailable }
        return ink
    }

    func undoLastEdit() {
        guard let edit = history.popLast() else { return }
        discardLiveInk()
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
        discardLiveInk()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // A fully transparent area of a macOS window can pass clicks through.
        NSColor.black.withAlphaComponent(0.01).setFill()
        dirtyRect.fill(using: .copy)
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            for stroke in strokes where stroke !== live.stroke { stroke.draw(in: context, dirtyRect: dirtyRect) }
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
