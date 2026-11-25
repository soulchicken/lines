import AppKit

enum PenColor: Int, CaseIterable {
    case red = 1, blue, green, yellow

    var name: String {
        switch self {
        case .red: return "빨강"
        case .blue: return "파랑"
        case .green: return "초록"
        case .yellow: return "노랑"
        }
    }

    var ink: NSColor {
        switch self {
        case .red: return NSColor(srgbRed: 0.97, green: 0.20, blue: 0.23, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.12, green: 0.45, blue: 0.98, alpha: 1)
        case .green: return NSColor(srgbRed: 0.04, green: 0.64, blue: 0.33, alpha: 1)
        case .yellow: return NSColor(srgbRed: 0.98, green: 0.77, blue: 0.05, alpha: 1)
        }
    }
}

final class PenPalette: NSObject, NSMenuDelegate {
    private(set) var selected = PenColor(rawValue: UserDefaults.standard.integer(forKey: "penColor")) ?? .red
    var shortcutLabels: [PenColor: String] = [:]
    var onChange: (() -> Void)?

    func select(_ color: PenColor) {
        selected = color
        UserDefaults.standard.set(color.rawValue, forKey: "penColor")
        onChange?()
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "펜 색상")
        menu.delegate = self
        for color in PenColor.allCases {
            let item = menu.addItem(withTitle: "\(color.rawValue)   \(color.name)",
                                    action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.tag = color.rawValue
            item.image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
                color.ink.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                return true
            }
        }
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            if let color = PenColor(rawValue: item.tag) {
                item.title = (shortcutLabels[color] ?? String(color.rawValue)) + "   " + color.name
            }
            item.state = item.tag == selected.rawValue ? .on : .off
        }
    }

    @objc private func choose(_ sender: NSMenuItem) {
        if let color = PenColor(rawValue: sender.tag) { select(color) }
    }
}
