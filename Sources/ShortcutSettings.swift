import AppKit
import Carbon.HIToolbox

final class ShortcutSettings: NSObject, NSWindowDelegate {
    let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 550),
                         styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
    private let message = NSTextField(wrappingLabelWithString: "")
    private var buttons: [ShortcutAction: NSButton] = [:]
    private(set) var recording: ShortcutAction?
    private let binding: (ShortcutAction) -> KeyBinding
    private let assign: (ShortcutAction, KeyBinding) -> String?
    var onClose: (() -> Void)?

    init(binding: @escaping (ShortcutAction) -> KeyBinding,
         assign: @escaping (ShortcutAction, KeyBinding) -> String?) {
        self.binding = binding
        self.assign = assign
        super.init()
        window.title = "Lines 설정"
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        for action in ShortcutAction.allCases {
            if action == .toggle || action == .undo {
                let heading = NSTextField(labelWithString: action == .toggle ? "모든 앱에서" : "필기 중")
                heading.font = .boldSystemFont(ofSize: 13)
                stack.addArrangedSubview(heading)
            }
            let title = NSTextField(labelWithString: action.title)
            let button = NSButton(title: "", target: self, action: #selector(startRecording(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(action.rawValue)
            button.setAccessibilityLabel(action.title + " 단축키 변경")
            buttons[action] = button
            let row = NSStackView(views: [title, NSView(), button])
            row.orientation = .horizontal
            row.alignment = .centerY
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            button.widthAnchor.constraint(equalToConstant: 132).isActive = true
            if action == .toggle { stack.setCustomSpacing(16, after: row) }
        }
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor
        stack.setCustomSpacing(14, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(message)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            message.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        let reset = NSButton(title: "기본 단축키로 복원", target: self, action: #selector(restoreDefaults))
        reset.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(reset)
        NSLayoutConstraint.activate([
            reset.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            reset.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18)
        ])
        window.center()
    }

    var reset: (() -> String?)?

    func show(warning: String? = nil) {
        refresh(warning)
        window.makeKeyAndOrderFront(nil)
    }

    private func refresh(_ notice: String? = nil) {
        for (action, button) in buttons {
            button.title = recording == action ? "키를 누르세요…" : binding(action).label
        }
        message.stringValue = notice ?? (recording == nil
            ? "바꿀 단축키를 클릭한 뒤 새 키를 누르세요."
            : "새 단축키를 누르세요. Esc를 누르면 취소합니다.")
    }

    @objc private func startRecording(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let action = ShortcutAction(rawValue: id) else { return }
        recording = recording == action ? nil : action
        refresh()
    }

    func record(_ key: KeyBinding) {
        guard let recording else { return }
        if let error = assign(recording, key) {
            refresh(error)
        } else {
            self.recording = nil
            refresh()
        }
    }

    func handle(_ event: NSEvent) -> Bool {
        guard recording != nil else { return false }
        if event.isARepeat { return true }
        if let key = KeyBinding(event: event) {
            if key.code == UInt32(kVK_Escape) && key.modifiers == 0 {
                recording = nil
                refresh()
            } else {
                record(key)
            }
        }
        return true
    }

    @objc private func restoreDefaults() {
        recording = nil
        refresh(reset?())
    }

    func windowDidResignKey(_ notification: Notification) {
        recording = nil
        refresh()
    }

    func windowWillClose(_ notification: Notification) {
        recording = nil
        onClose?()
    }
}
