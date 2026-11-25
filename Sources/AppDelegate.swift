import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let toggleItem = NSMenuItem()
    private let palette = PenPalette()
    private var shortcutMonitor: Any?
    private var statusItem: NSStatusItem!
    private(set) var panel: InkPanel?
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        toggleItem.target = self
        toggleItem.action = #selector(toggleInk)
        menu.addItem(toggleItem)
        if !registerShortcut() {
            menu.addItem(withTitle: "단축키를 사용할 수 없어요. 메뉴에서 펜을 켜세요.",
                         action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        let colors = menu.addItem(withTitle: "펜 색상", action: nil, keyEquivalent: "")
        colors.submenu = palette.makeMenu()
        palette.onChange = { [weak self] in self?.panel?.canvas.showColorHint() }
        menu.addItem(withTitle: "⌘Z   실행 취소", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Delete   전체 지우기", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Esc   필기 마치기", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Lines 종료", action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q").target = NSApp
        statusItem.menu = menu
        updateStatus()
    }

    @objc func toggleInk() {
        if panel != nil {
            finishInk()
            return
        }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
        else { return }
        let overlay = InkPanel(on: screen, palette: palette)
        overlay.onFinish = { [weak self] in self?.finishInk() }
        panel = overlay
        overlay.makeKeyAndOrderFront(nil)
        overlay.makeFirstResponder(overlay.canvas)
        // Intercept Command shortcuts before AppKit sends key equivalents to a menu.
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak overlay] event in
            guard let overlay, (event.window ?? NSApp.keyWindow) === overlay else { return event }
            return overlay.handleShortcut(event) ? nil : event
        }
        updateStatus()
    }

    private func finishInk() {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        updateStatus()
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        if panel != nil { finishInk() }
    }

    private func updateStatus() {
        let active = panel != nil
        let label = active ? "필기 마치기" : "필기 시작"
        toggleItem.title = hotKey == nil ? label : label + "    ⌃⌥D"
        let symbol = active ? "pencil.circle.fill" : "pencil.circle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Lines · " + label)
        statusItem.button?.toolTip = "Lines · " + toggleItem.title
    }

    private func registerShortcut() -> Bool {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyReleased))
        let id = EventHotKeyID(signature: 0x4C494E45, id: 1) // LINE
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var received = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &received)
            guard result == noErr, received.signature == 0x4C494E45, received.id == 1
            else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            delegate.toggleInk()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return false }
        return RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey), id,
                                   GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey) == noErr
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
