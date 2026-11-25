import AppKit

final class InkToolbar: NSStackView {
    private let palette: PenPalette
    private let pen = NSButton()
    private let line = NSButton()
    private let laser = NSButton()
    private let rectangle = NSButton()
    private let text = NSButton()
    private let capture = NSButton()
    private let undo = NSButton()
    private let finish = NSButton()
    private var selectedTool: InkCanvas.Tool = .pen
    var onSelectTool: ((InkCanvas.Tool) -> Void)?
    var makeColorMenu: ((InkCanvas.Tool) -> NSMenu?)?
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
        add(line, "직선", "line.diagonal", #selector(chooseLine))
        add(rectangle, "사각형", "rectangle", #selector(chooseRectangle))
        add(text, "텍스트", "textformat", #selector(chooseText))
        add(laser, "레이저", "scope", #selector(chooseLaser))
        let divider = NSBox()
        divider.boxType = .separator
        addArrangedSubview(divider)
        divider.heightAnchor.constraint(equalToConstant: 16).isActive = true
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        add(capture, "캡처", "camera", #selector(takeCapture))
        add(undo, "취소", "arrow.uturn.backward", #selector(undoEdit))
        add(finish, "종료", "xmark", #selector(finishInk))
        for button in [pen, line, rectangle, text, laser] {
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
        for (button, mode) in [(pen, InkCanvas.Tool.pen), (line, .line), (rectangle, .rectangle), (text, .text), (laser, .laser)] {
            button.state = tool == mode ? .on : .off
            button.layer?.backgroundColor = tool == mode
                ? NSColor.white.withAlphaComponent(0.16).cgColor : nil
        }
        pen.toolTip = "펜 선택 (" + shortcuts[.pen].label + ")"
        line.toolTip = "직선 선택 (" + shortcuts[.line].label + ") · ⌥를 누른 채 드래그하면 화살표"
        rectangle.toolTip = "사각형 선택 (" + shortcuts[.rectangle].label + ")"
        text.toolTip = "텍스트 선택 (" + shortcuts[.text].label + ") · 클릭하여 입력하거나 기존 글을 드래그해 이동"
        laser.toolTip = "레이저 선택 (" + shortcuts[.laser].label + ") · 우클릭하여 사라지는 시간 설정"
        capture.toolTip = "필기를 포함한 PNG 저장 (" + shortcuts[.capture].label + ")"
        undo.toolTip = "실행 취소 (" + shortcuts[.undo].label + ")"
        finish.toolTip = "필기 마치기 (" + shortcuts[.finish].label + ")"
    }

    private func choose(_ tool: InkCanvas.Tool, button: NSButton) {
        if selectedTool != tool {
            onSelectTool?(tool)
            return
        }
        button.state = .on
        makeColorMenu?(tool)?.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: button)
    }

    @objc private func choosePen() { choose(.pen, button: pen) }
    @objc private func chooseLine() { choose(.line, button: line) }
    @objc private func chooseRectangle() { choose(.rectangle, button: rectangle) }
    @objc private func chooseText() { choose(.text, button: text) }
    @objc private func chooseLaser() { choose(.laser, button: laser) }
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
