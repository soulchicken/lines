import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var isCapturing = false
    private let laserItem = NSMenuItem()
    private let captureItem = NSMenuItem()
    private let toggleItem = NSMenuItem()
    private let warningItem = NSMenuItem(title: "전역 단축키를 설정에서 변경하세요.", action: nil, keyEquivalent: "")
    private var editItems: [ShortcutAction: NSMenuItem] = [:]
    private let palette = PenPalette()
    private var shortcuts = Shortcuts()
    private var settings: ShortcutSettings?
    private var shortcutMonitor: Any?
    private var statusItem: NSStatusItem!
    private(set) var panel: InkPanel?
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var hotKeyID: UInt32 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        toggleItem.target = self
        toggleItem.action = #selector(toggleInk)
        menu.addItem(toggleItem)
        menu.addItem(warningItem)
        laserItem.target = self
        laserItem.action = #selector(toggleLaser)
        menu.addItem(laserItem)
        captureItem.target = self
        captureItem.action = #selector(captureScreen)
        menu.addItem(captureItem)
        menu.addItem(.separator())
        let colors = menu.addItem(withTitle: "펜 색상", action: nil, keyEquivalent: "")
        colors.submenu = palette.makeMenu()
        palette.onChange = { [weak self] in self?.updateStatus() }
        for action in [ShortcutAction.undo, .clear, .finish] {
            editItems[action] = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "설정…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Lines 종료", action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q").target = NSApp
        statusItem.menu = menu
        _ = registerToggle(shortcuts[.toggle])
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) == true ? nil : event
        }
        updateStatus()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let window = event.window ?? NSApp.keyWindow else { return false }
        let inSettings = window === settings?.window
        if inSettings, settings?.handle(event) == true { return true }
        guard inSettings || (window === panel && panel?.isVisible == true),
              let key = KeyBinding(event: event) else { return false }
        if let canvas = panel?.canvas, let editor = canvas.textEditor, window.firstResponder === editor {
            // Leave typing, text editing and input method composition to AppKit.
            guard !editor.hasMarkedText() else { return false }
            if key.sameKeys(as: KeyBinding(kVK_Escape, "Esc")) {
                canvas.cancelText()
                return true
            }
            if key.modifiers == UInt32(cmdKey), key.code == UInt32(kVK_Return) || key.code == UInt32(kVK_ANSI_KeypadEnter) {
                canvas.commitText()
                return true
            }
            if key.opensSettings { openSettings(); return true }
            if key.modifiers & UInt32(cmdKey) != 0, shortcuts.action(for: key) == .capture {
                captureScreen()
                return true
            }
            return false
        }
        if key.opensSettings {
            openSettings()
            return true
        }
        if inSettings {
            if key.sameKeys(as: KeyBinding(kVK_ANSI_W, "W", cmdKey)) {
                settings?.window.close()
                return true
            }
            return false
        }
        guard let action = shortcuts.action(for: key), action != .toggle else { return false }
        if action == .laser && event.isARepeat { return true }
        panel?.perform(action)
        return true
    }

    @objc private func openSettings() {
        guard !isCapturing else { return }
        panel?.canvas.commitText()
        if settings == nil {
            let controller = ShortcutSettings(binding: { [unowned self] in self.shortcuts[$0] },
                                              assign: { [unowned self] in self.assign($0, $1) })
            controller.reset = { [unowned self] in
                var defaults = self.shortcuts
                for action in ShortcutAction.allCases { defaults[action] = action.defaultKey }
                return self.apply(defaults, retryGlobal: true)
            }
            controller.onClose = { [weak self] in self?.showInkPanel() }
            settings = controller
        }
        panel?.orderOut(nil)
        settings?.window.level = panel == nil ? .floating : .screenSaver
        settings?.show(warning: hotKey == nil ? "전역 단축키를 등록할 수 없어요. 다른 조합을 선택하세요." : nil)
    }

    private func assign(_ action: ShortcutAction, _ key: KeyBinding) -> String? {
        if key.opensSettings { return "⌘,는 설정 열기에 사용됩니다." }
        if action == .toggle && key.modifiers & UInt32(cmdKey | optionKey | controlKey) == 0 {
            return "전역 단축키에는 ⌘, ⌥, ⌃ 중 하나를 포함하세요."
        }
        if let other = ShortcutAction.allCases.first(where: { $0 != action && shortcuts[$0].sameKeys(as: key) }) {
            return "이미 ‘" + other.title + "’에 지정된 단축키입니다."
        }
        var updated = shortcuts
        updated[action] = key
        return apply(updated, retryGlobal: action == .toggle)
    }

    private func apply(_ updated: Shortcuts, retryGlobal: Bool) -> String? {
        if !updated[.toggle].sameKeys(as: shortcuts[.toggle]) || (retryGlobal && hotKey == nil) {
            guard registerToggle(updated[.toggle]) else {
                return "전역 단축키를 등록할 수 없어요. 다른 조합을 선택하세요."
            }
        }
        shortcuts = updated
        shortcuts.persist()
        updateStatus()
        return nil
    }

    @objc func toggleInk() {
        guard !isCapturing else { return }
        settings?.window.orderOut(nil)
        if panel != nil {
            finishInk()
            return
        }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
        else { return }
        let overlay = InkPanel(on: screen, palette: palette)
        overlay.onFinish = { [weak self] in self?.finishInk() }
        overlay.onToggleLaser = { [weak self] in self?.toggleLaser() }
        overlay.onCapture = { [weak self] in self?.captureScreen() }
        overlay.canvas.onToolChange = { [weak self] in self?.updateStatus() }
        panel = overlay
        updateStatus()
        showInkPanel()
    }

    @objc private func toggleLaser() {
        guard !isCapturing else { return }
        if panel == nil { toggleInk() }
        if panel?.isVisible == false {
            settings?.window.orderOut(nil)
            showInkPanel()
        }
        panel?.canvas.toggleLaser()
    }

    @objc private func captureScreen() {
        let screen = panel?.screen ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard !isCapturing, let screen,
              let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return }
        isCapturing = true
        panel?.canvas.commitText()
        let resumeInk = panel?.isVisible == true
        Task { @MainActor in
            defer {
                isCapturing = false
                if resumeInk { showInkPanel() }
            }
            do {
                let ink = try panel?.canvas.snapshotInk(scale: screen.backingScaleFactor)
                if resumeInk { panel?.orderOut(nil) }
                let image = try await ScreenCapture.image(displayID: display.uint32Value, ink: ink)
                if let url = ScreenCapture.chooseDestination() {
                    try await Task.detached { try ScreenCapture.writePNG(image, to: url) }.value
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "화면 캡처를 저장할 수 없어요."
                let failure = error as NSError
                if failure.domain == SCStreamErrorDomain && failure.code == SCStreamError.Code.userDeclined.rawValue {
                    alert.informativeText = "시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 녹음에서 Lines를 허용한 뒤 다시 시도하세요."
                } else {
                    alert.informativeText = error.localizedDescription
                }
                alert.window.level = .screenSaver
                alert.runModal()
            }
        }
    }

    private func showInkPanel() {
        guard let panel else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.canvas)
    }

    private func finishInk() {
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
        toggleItem.title = hotKey == nil ? label : label + "    " + shortcuts[.toggle].label
        warningItem.isHidden = hotKey != nil
        laserItem.title = (panel?.canvas.isLaserActive == true ? "펜으로 전환" : "레이저 포인터")
            + (active ? "    " + shortcuts[.laser].label : "")
        captureItem.title = "화면 캡처…" + (active ? "    " + shortcuts[.capture].label : "")
        for (action, item) in editItems { item.title = shortcuts[action].label + "   " + action.title }
        palette.shortcutLabels = [.red: shortcuts[.red].label, .blue: shortcuts[.blue].label,
                                  .green: shortcuts[.green].label, .yellow: shortcuts[.yellow].label]
        if let canvas = panel?.canvas {
            canvas.toolbar.refresh(tool: canvas.tool, shortcuts: shortcuts)
        }
        statusItem.button?.image = Self.statusImage(active: active)
        statusItem.button?.setAccessibilityLabel("Lines · " + label)
        statusItem.button?.toolTip = "Lines · " + toggleItem.title
    }

    private static func statusImage(active: Bool) -> NSImage? {
        guard let pen = NSImage(named: "MenuPen") else {
            return NSImage(systemSymbolName: active ? "pencil.circle.fill" : "pencil.circle",
                           accessibilityDescription: nil)
        }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            pen.draw(in: rect)
            if active {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 13, y: 1, width: 4, height: 4)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private func installHandler() -> Bool {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        return InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var received = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &received)
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            guard result == noErr, received.signature == 0x4C494E45, received.id == delegate.hotKeyID
            else { return OSStatus(eventNotHandledErr) }
            if let settings = delegate.settings, settings.window.isKeyWindow, settings.recording != nil {
                settings.record(delegate.shortcuts[.toggle])
            } else {
                delegate.toggleInk()
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler) == noErr
    }

    private func registerToggle(_ key: KeyBinding) -> Bool {
        guard handler != nil || installHandler() else { return false }
        var replacement: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x4C494E45, id: hotKeyID &+ 1)
        // Reserve the new combination before releasing the working shortcut.
        guard RegisterEventHotKey(key.code, key.modifiers, id, GetApplicationEventTarget(),
                                  OptionBits(kEventHotKeyExclusive), &replacement) == noErr else { return false }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        hotKeyID = id.id
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
