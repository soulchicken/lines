import AppKit
import Carbon.HIToolbox

enum ShortcutAction: String, CaseIterable {
    case toggle, pen, line, text, rectangle, laser, undo, clear, finish, capture, red, blue, green, yellow

    static let toolSelections: [Self] = [.pen, .line, .text, .rectangle, .laser]

    var title: String {
        switch self {
        case .toggle: return "필기 시작 / 마치기"
        case .pen: return "펜 선택"
        case .line: return "직선 선택"
        case .text: return "텍스트 선택"
        case .rectangle: return "사각형 선택"
        case .laser: return "레이저 선택"
        case .undo: return "실행 취소"
        case .clear: return "전체 지우기"
        case .finish: return "필기 마치기"
        case .capture: return "화면 캡처"
        case .red: return "빨강 펜"
        case .blue: return "파랑 펜"
        case .green: return "초록 펜"
        case .yellow: return "노랑 펜"
        }
    }

    var defaultKey: KeyBinding {
        switch self {
        case .toggle: return KeyBinding(kVK_ANSI_Grave, "`", optionKey)
        case .pen: return KeyBinding(kVK_ANSI_Q, "Q")
        case .line: return KeyBinding(kVK_ANSI_W, "W")
        case .text: return KeyBinding(kVK_ANSI_E, "E")
        case .rectangle: return KeyBinding(kVK_ANSI_R, "R")
        case .laser: return KeyBinding(kVK_ANSI_A, "A")
        case .undo: return KeyBinding(kVK_ANSI_Z, "Z", cmdKey)
        case .clear: return KeyBinding(kVK_Delete, "Delete")
        case .finish: return KeyBinding(kVK_Escape, "Esc")
        case .capture: return KeyBinding(kVK_ANSI_S, "S", cmdKey)
        case .red: return KeyBinding(kVK_ANSI_1, "1")
        case .blue: return KeyBinding(kVK_ANSI_2, "2")
        case .green: return KeyBinding(kVK_ANSI_3, "3")
        case .yellow: return KeyBinding(kVK_ANSI_4, "4")
        }
    }
}

struct KeyBinding: Codable {
    let code: UInt32
    let modifiers: UInt32
    let key: String

    init(_ code: Int, _ key: String, _ modifiers: Int = 0) {
        self.code = UInt32(code)
        self.modifiers = UInt32(modifiers)
        self.key = key
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var mask = 0
        if flags.contains(.command) { mask |= cmdKey }
        if flags.contains(.option) { mask |= optionKey }
        if flags.contains(.control) { mask |= controlKey }
        if flags.contains(.shift) { mask |= shiftKey }
        let name: String
        switch Int(event.keyCode) {
        case kVK_Escape: name = "Esc"
        case kVK_Delete: name = "Delete"
        case kVK_ForwardDelete: name = "⌦"
        case kVK_Return, kVK_ANSI_KeypadEnter: name = "↩"
        case kVK_Tab: name = "⇥"
        case kVK_Space: name = "Space"
        case kVK_LeftArrow: name = "←"
        case kVK_RightArrow: name = "→"
        case kVK_UpArrow: name = "↑"
        case kVK_DownArrow: name = "↓"
        default:
            guard let text = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers,
                  let scalar = text.unicodeScalars.first else { return nil }
            if (0xF704...0xF726).contains(scalar.value) {
                name = "F" + String(scalar.value - 0xF703)
            } else {
                guard !CharacterSet.controlCharacters.contains(scalar),
                      !(0xF700...0xF8FF).contains(scalar.value) else { return nil }
                name = text.uppercased()
            }
        }
        self.init(Int(event.keyCode), name, mask)
    }

    var label: String {
        let parts = [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
        return parts.filter { modifiers & UInt32($0.0) != 0 }.map { $0.1 }.joined() + key
    }

    func sameKeys(as other: KeyBinding) -> Bool {
        code == other.code && modifiers == other.modifiers
    }

    var opensSettings: Bool {
        modifiers == UInt32(cmdKey) && (code == UInt32(kVK_ANSI_Comma) || key == ",")
    }
}

struct Shortcuts {
    private var saved: [String: KeyBinding] = [:]

    init(loadSaved: Bool = true) {
        if loadSaved, let data = UserDefaults.standard.data(forKey: "shortcuts.v1"),
           let values = try? JSONDecoder().decode([String: KeyBinding].self, from: data) {
            saved = values
            // A new default must not take over a key the user already assigned.
            for action in [.toggle, .capture] + ShortcutAction.toolSelections where saved[action.rawValue] == nil {
                let key = action.defaultKey
                guard saved.values.contains(where: { $0.sameKeys(as: key) }) else { continue }
                let masks = [cmdKey | shiftKey, cmdKey | optionKey, cmdKey | controlKey,
                             optionKey | shiftKey, controlKey | shiftKey, controlKey | optionKey,
                             cmdKey | shiftKey | optionKey, cmdKey | shiftKey | controlKey,
                             controlKey, optionKey, shiftKey]
                var alternatives = masks.map { KeyBinding(Int(key.code), key.key, $0) }
                if action == .toggle {
                    alternatives.insert(KeyBinding(kVK_ANSI_D, "D", controlKey | optionKey), at: 0)
                }
                saved[action.rawValue] = alternatives.first { candidate in
                    !saved.values.contains(where: { $0.sameKeys(as: candidate) })
                }
            }
        }
    }

    subscript(action: ShortcutAction) -> KeyBinding {
        get { saved[action.rawValue] ?? action.defaultKey }
        set { saved[action.rawValue] = newValue }
    }

    func action(for binding: KeyBinding) -> ShortcutAction? {
        if let exact = ShortcutAction.allCases.first(where: { self[$0].sameKeys(as: binding) }) {
            return exact
        }
        // Preserve the original alternate inputs for the default editing shortcuts.
        if binding.modifiers == 0, binding.code == UInt32(kVK_ForwardDelete),
           self[.clear].sameKeys(as: ShortcutAction.clear.defaultKey) { return .clear }
        return ShortcutAction.allCases.first {
            $0 != .toggle && self[$0].sameKeys(as: $0.defaultKey)
                && binding.modifiers == self[$0].modifiers && binding.key == self[$0].key
        }
    }

    func persist() {
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: "shortcuts.v1")
        }
    }
}
