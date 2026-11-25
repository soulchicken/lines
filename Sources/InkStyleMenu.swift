import AppKit

enum InkStyleMenu {
    static let widths = [2, 4, 6, 8, 12]
    static let fontSizes = [14, 18, 22, 28, 36, 48, 64]

    static func stroke(_ style: InkStroke.Style, apply: @escaping (InkStroke.Style) -> Void) -> NSMenu {
        let menu = NSMenu()
        addColors(to: menu, selected: style.color) { color in
            var updated = style
            updated.color = color
            apply(updated)
        }
        addChoices(to: menu, title: "선 굵기", values: widths, selected: style.width, label: { String($0) + " pt" }) { width in
            var updated = style
            updated.width = width
            apply(updated)
        }
        return menu
    }

    static func text(_ style: InkText.Style, in menu: NSMenu = NSMenu(),
                     apply: @escaping (InkText.Style) -> Void) -> NSMenu {
        func update<Value>(_ key: WritableKeyPath<InkText.Style, Value>, to value: Value) {
            var updated = style
            updated[keyPath: key] = value
            apply(updated)
        }
        addColors(to: menu, selected: style.color) { update(\.color, to: $0) }
        addChoices(to: menu, title: "글자 크기", values: fontSizes, selected: style.size, label: { String($0) + " pt" }) {
            update(\.size, to: $0)
        }
        addChoices(to: menu, title: "글자 굵기", values: InkText.Style.Weight.allCases,
                   selected: style.weight, label: { $0.title }) { update(\.weight, to: $0) }
        menu.addItem(StyleMenuItem("기울임", isSelected: style.italic) { update(\.italic, to: !style.italic) })
        return menu
    }

    static func colors(selected: PenColor, apply: @escaping (PenColor) -> Void) -> NSMenu {
        let menu = NSMenu(title: "색상")
        for color in PenColor.allCases {
            let item = StyleMenuItem(color.name, isSelected: color == selected) { apply(color) }
            item.image = color.swatch
            menu.addItem(item)
        }
        return menu
    }

    private static func addColors(to menu: NSMenu, selected: PenColor, apply: @escaping (PenColor) -> Void) {
        let item = NSMenuItem(title: "색상", action: nil, keyEquivalent: "")
        item.submenu = colors(selected: selected, apply: apply)
        menu.addItem(item)
    }

    private static func addChoices<Value: Equatable>(to menu: NSMenu, title: String, values: [Value],
                                                     selected: Value, label: (Value) -> String,
                                                     apply: @escaping (Value) -> Void) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        for value in values {
            submenu.addItem(StyleMenuItem(label(value), isSelected: value == selected) { apply(value) })
        }
        item.submenu = submenu
        menu.addItem(item)
    }
}

private final class StyleMenuItem: NSMenuItem {
    private let choose: () -> Void

    init(_ title: String, isSelected: Bool, choose: @escaping () -> Void) {
        self.choose = choose
        super.init(title: title, action: #selector(selectValue), keyEquivalent: "")
        target = self
        state = isSelected ? .on : .off
    }

    required init(coder: NSCoder) { fatalError("Programmatic menu item") }

    @objc private func selectValue() { choose() }
}
