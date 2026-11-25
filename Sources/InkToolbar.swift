import AppKit

final class InkToolbar: NSStackView {
    private let palette: PenPalette
    private let pen = NSButton()
    private let laser = NSButton()
    private let rectangle = NSButton()
    private let text = NSButton()
    private let capture = NSButton()
    private let undo = NSButton()
    private let finish = NSButton()
    private var selectedTool: InkCanvas.Tool = .pen
    var onSelectTool: ((InkCanvas.Tool) -> Void)?
    var onAction: ((ShortcutAction) -> Void)?

    init(palette: PenPalette) {
        self.palette = palette
        super.init(frame: .zero)
        appearance = NSAppearance(named: .darkAqua)
        orientation = .horizontal
        alignment = .centerY
        spacing = 3
        edgeInsets = NSEdgeInsets(top: 4, left: 7, bottom: 4, right: 7)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.14, alpha: 0.95).cgColor
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        setAccessibilityLabel("필기 도구")

        add(pen, "펜", "pencil.tip", #selector(choosePen))
        add(rectangle, "사각형", "rectangle", #selector(chooseRectangle))
        add(text, "텍스트", "textformat", #selector(chooseText))
        add(laser, "레이저", "scope", #selector(toggleLaser))
        let divider = NSBox()
        divider.boxType = .separator
        addArrangedSubview(divider)
        divider.heightAnchor.constraint(equalToConstant: 16).isActive = true
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        add(capture, "캡처", "camera", #selector(takeCapture))
        add(undo, "취소", "arrow.uturn.backward", #selector(undoEdit))
        add(finish, "종료", "xmark", #selector(finishInk))
        for button in [pen, rectangle, text, laser] {
            button.setButtonType(.toggle)
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
        }
    }

    required init?(coder: NSCoder) { nil }

    private func add(_ button: NSButton, _ title: String, _ symbol: String, _ action: Selector) {
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .recessed
        button.showsBorderOnlyWhileMouseInside = true
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.contentTintColor = .white
        button.target = self
        button.action = action
        addArrangedSubview(button)
    }

    func refresh(tool: InkCanvas.Tool, shortcuts: Shortcuts) {
        selectedTool = tool
        pen.title = palette.selected.name + " 펜"
        for (button, mode) in [(pen, InkCanvas.Tool.pen), (rectangle, .rectangle), (text, .text), (laser, .laser)] {
            button.state = tool == mode ? .on : .off
            button.layer?.backgroundColor = tool == mode
                ? NSColor.white.withAlphaComponent(0.16).cgColor : nil
        }
        pen.toolTip = tool == .pen ? "펜 색상 선택" : "펜으로 전환"
        rectangle.toolTip = "드래그하여 사각형 그리기"
        text.toolTip = "빈 곳을 클릭해 입력하거나 기존 글을 드래그해 이동"
        laser.toolTip = "펜 / 레이저 전환 (" + shortcuts[.laser].label + ")"
        capture.toolTip = "필기를 포함한 PNG 저장 (" + shortcuts[.capture].label + ")"
        undo.toolTip = "실행 취소 (" + shortcuts[.undo].label + ")"
        finish.toolTip = "필기 마치기 (" + shortcuts[.finish].label + ")"
    }

    @objc private func choosePen() {
        if selectedTool != .pen { onSelectTool?(.pen); return }
        pen.state = .on
        palette.makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: pen)
    }

    @objc private func chooseRectangle() {
        rectangle.state = .on
        onSelectTool?(.rectangle)
    }

    @objc private func chooseText() {
        text.state = .on
        onSelectTool?(.text)
    }

    @objc private func toggleLaser() { onAction?(.laser) }
    @objc private func takeCapture() { onAction?(.capture) }
    @objc private func undoEdit() { onAction?(.undo) }
    @objc private func finishInk() { onAction?(.finish) }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    // Consume clicks in the padding and between controls before they reach the canvas.
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}
