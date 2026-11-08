import AppKit
import IShotCore
import ScreenCaptureKit

@main struct IShotMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: NSStatusItem!
    private let capture = CaptureCoordinator()
    private var hotKeys: HotKeyManager!
    private var settings: SettingsController?
    private var welcome: WelcomeController?
    private var editors: [UUID: EditorController] = [:]
    private var pins: [UUID: PinController] = [:]
    private var pinsHidden = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("--light") { NSApp.appearance = NSAppearance(named: .aqua) }
        setupMainMenu()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "ishot 截图")
        status.button?.toolTip = "ishot · 截图与贴图"
        let menu = NSMenu()
        func add(_ title: String, _ selector: Selector) {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        add("区域截图", #selector(region)); add("当前显示器全屏截图", #selector(fullscreen)); menu.addItem(.separator())
        add("显示 / 隐藏全部贴图", #selector(togglePins)); add("关闭全部贴图…", #selector(closePins)); menu.addItem(.separator())
        add("设置…", #selector(openSettings)); add("使用指南 / 示例图", #selector(openWelcome)); menu.addItem(.separator()); add("退出 ishot", #selector(quit))
        status.menu = menu
        capture.onImage = { [weak self] image, pin in if pin { self?.addPin(image) } else { self?.edit(image) } }
        hotKeys = HotKeyManager()
        hotKeys.onAction = { [weak self] index in
            guard let self else { return }
            switch index { case 0: self.region(); case 1: self.fullscreen(); case 2: self.togglePins(); default: break }
        }
        let isSmoke = ProcessInfo.processInfo.arguments.contains("--smoke-test")
        let isCaptureCheck = ProcessInfo.processInfo.arguments.contains("--capture-check")
        let isPreview = ProcessInfo.processInfo.arguments.contains("--preview")
        if !isSmoke && !isCaptureCheck && !hotKeys.apply(hotKeys.shortcuts, persist: false) {
            DispatchQueue.main.async { showError("部分快捷键无法注册。你仍可通过菜单栏截图，也可以在设置中换一组快捷键。") }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if isSmoke { smokeTest(); return }
        if isCaptureCheck {
            guard CGPreflightScreenCaptureAccess() else {
                print("CAPTURE SKIP: screen recording permission has not been granted to this app")
                NSApp.terminate(nil); return
            }
            capture.onFailure = { error in
                fputs("CAPTURE FAIL: \(error.localizedDescription)\n", stderr); exit(1)
            }
            capture.onImage = { image, _ in
                precondition(image.width > 0 && image.height > 0)
                print("CAPTURE PASS: ScreenCaptureKit returned \(image.width) × \(image.height) pixels. Desktop image was not saved.")
                NSApp.terminate(nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
                fputs("CAPTURE FAIL: timed out\n", stderr); exit(1)
            }
            capture.start(fullscreen: true); return
        }
        if isPreview { edit(makeDemoImage()); return }
        if !UserDefaults.standard.bool(forKey: "didWelcome") {
            openWelcome(); UserDefaults.standard.set(true, forKey: "didWelcome")
        }
    }
    private func setupMainMenu() {
        let root = NSMenu()
        let app = NSMenuItem(); let appMenu = NSMenu()
        let quit = NSMenuItem(title: "退出 ishot", action: #selector(quit), keyEquivalent: "q"); quit.target = self; appMenu.addItem(quit); app.submenu = appMenu; root.addItem(app)
        let edit = NSMenuItem(); edit.title = "编辑"; let editMenu = NSMenu(title: "编辑")
        for (title, selector, key, shift) in [("撤销", Selector(("undo:")), "z", false), ("重做", Selector(("redo:")), "z", true), ("剪切", #selector(NSText.cut(_:)), "x", false), ("复制", #selector(NSText.copy(_:)), "c", false), ("粘贴", #selector(NSText.paste(_:)), "v", false), ("全选", #selector(NSText.selectAll(_:)), "a", false)] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            if key == "z" { item.action = shift ? #selector(routeRedo(_:)) : #selector(routeUndo(_:)); item.target = self }
            item.keyEquivalentModifierMask = shift ? [.command, .shift] : .command; editMenu.addItem(item)
        }
        edit.submenu = editMenu; root.addItem(edit); NSApp.mainMenu = root
    }
    // NSWindow implements undo: for its own NSUndoManager before the controller is
    // reached. Route image history explicitly while preserving text field undo.
    @objc private func routeUndo(_ sender: Any?) {
        if let editor = NSApp.keyWindow?.windowController as? EditorController, !(NSApp.keyWindow?.firstResponder is NSTextView) { editor.undo(sender) }
        else { NSApp.sendAction(Selector(("undo:")), to: nil, from: sender) }
    }
    @objc private func routeRedo(_ sender: Any?) {
        if let editor = NSApp.keyWindow?.windowController as? EditorController, !(NSApp.keyWindow?.firstResponder is NSTextView) { editor.redo(sender) }
        else { NSApp.sendAction(Selector(("redo:")), to: nil, from: sender) }
    }
    func edit(_ image: CGImage, apply: ((CGImage) -> Void)? = nil) {
        let id = UUID(); let controller = EditorController(image: image, apply: apply)
        controller.onPin = { [weak self] image in self?.addPin(image) }
        controller.onClose = { [weak self] in DispatchQueue.main.async { self?.editors.removeValue(forKey: id) } }
        editors[id] = controller; controller.present()
    }
    func addPin(_ image: CGImage) {
        let id = UUID(); let controller = PinController(image: image)
        controller.onClose = { [weak self] in DispatchQueue.main.async { self?.pins.removeValue(forKey: id) } }
        controller.onEdit = { [weak self] image, apply in self?.edit(image, apply: apply) }
        if pinsHidden { pins.values.forEach { $0.present() }; pinsHidden = false }
        pins[id] = controller; controller.present()
    }
    @objc private func region() { capture.start() }
    @objc private func fullscreen() { capture.start(fullscreen: true) }
    @objc private func togglePins() {
        guard !capture.isSelecting else { return }
        pinsHidden.toggle()
        pins.values.forEach { if pinsHidden { $0.window?.orderOut(nil) } else { $0.present() } }
    }
    @objc private func closePins() {
        guard !pins.isEmpty else { return }
        let alert = NSAlert(); alert.messageText = "关闭全部 \(pins.count) 张贴图？"; alert.informativeText = "未保存的图片将丢失。"; alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "关闭全部")
        if alert.runModal() == .alertSecondButtonReturn { Array(pins.values).forEach { $0.close() }; pins.removeAll() }
    }
    @objc private func openSettings() { if settings == nil { settings = SettingsController(hotKeys: hotKeys) }; settings?.present() }
    @objc private func openWelcome() {
        if welcome == nil {
            welcome = WelcomeController(); welcome?.onCapture = { [weak self] in self?.region() }; welcome?.onDemo = { [weak self] in self?.edit(makeDemoImage()) }
        }
        welcome?.present()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func screensChanged() {
        capture.cancel()
        // Bring orphaned pins back after a monitor is disconnected.
        for pin in pins.values {
            guard let window = pin.window, !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) else { continue }
            window.center()
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") { return .terminateNow }
        guard !pins.isEmpty || !editors.isEmpty else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "退出 ishot？"; alert.informativeText = "未保存的贴图和批注会丢失。请先保存需要保留的图片。"; alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "退出")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
    private func smokeTest() {
        let image = makeDemoImage()
        edit(image); addPin(image); addPin(image)
        openSettings(); settings?.present(tab: "截图"); openWelcome()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            precondition(editors.count == 1 && pins.count == 2)
            let pin = pins.values.first!; let old = pin.window!.frame.width
            pin.zoom(by: 0.75); precondition(pin.window!.frame.width < old)
            pin.locked = true; let lockedWidth = pin.window!.frame.width; pin.zoom(by: 1.2); precondition(pin.window!.frame.width == lockedWidth)
            pin.setOpacity(0.4); precondition(pin.window!.alphaValue == 0.4)
            togglePins(); precondition(pins.values.allSatisfy { $0.window?.isVisible == false })
            togglePins(); precondition(pins.values.allSatisfy { $0.window?.isVisible == true })
            let editor = editors.values.first!
            editor.imageDocument.add(Annotation(tool: .arrow, points: [CGPoint(x: 100, y: 300), CGPoint(x: 700, y: 400)])); editor.refresh()
            precondition(editor.imageDocument.pngData() != nil)
            editor.window?.makeKeyAndOrderFront(nil); editor.window?.makeFirstResponder(editor.canvas)
            precondition(NSApp.sendAction(#selector(routeUndo(_:)), to: self, from: nil))
            precondition(editor.imageDocument.marks.isEmpty)
            precondition(NSApp.sendAction(#selector(routeRedo(_:)), to: self, from: nil))
            precondition(editor.imageDocument.marks.count == 1)
            precondition(!hotKeys.apply([Shortcut.defaults[0], Shortcut.defaults[0], Shortcut.defaults[2]], persist: false))
            if let pathIndex = ProcessInfo.processInfo.arguments.firstIndex(of: "--output"), ProcessInfo.processInfo.arguments.count > pathIndex + 1 {
                let url = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[pathIndex + 1]); try? editor.imageDocument.pngData()?.write(to: url)
                let directory = url.deletingLastPathComponent()
                func snapshot(_ view: NSView?, _ name: String) {
                    guard let view else { return }
                    view.layoutSubtreeIfNeeded()
                    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name))
                }
                snapshot(editor.window?.contentView, "editor.png")
                snapshot(welcome?.window?.contentView, "welcome.png")
                snapshot(settings?.window?.contentView, "settings.png")
                snapshot(pin.window?.contentView, "pin.png")

            }
            let arguments = ProcessInfo.processInfo.arguments
            let outputDirectory: URL?
            if let index = arguments.firstIndex(of: "--output"), arguments.count > index + 1 {
                outputDirectory = URL(fileURLWithPath: arguments[index + 1]).deletingLastPathComponent()
            } else { outputDirectory = nil }
            runSelectionChecks(image: image, outputDirectory: outputDirectory)
            print("SMOKE PASS: editor, 2 pins, zoom, lock, opacity, hide/show, settings, welcome, undo/redo responder routing, duplicate shortcuts, PNG export")
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--output"), ProcessInfo.processInfo.arguments.count > index + 1, CGPreflightScreenCaptureAccess() {
                let directory = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[index + 1]).deletingLastPathComponent()
                Task {
                    do {
                        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                        // Capture only this app's own windows, never the desktop or other apps.
                        for (window, name) in [(editor.window, "editor"), (welcome?.window, "welcome"), (settings?.window, "settings")] {
                            guard let window, let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else { continue }
                            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                            let config = SCStreamConfiguration(); config.showsCursor = false
                            config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
                            config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
                            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
                        }
                        print("UI SNAPSHOTS PASS: own-window ScreenCaptureKit capture")
                    } catch { print("UI snapshots unavailable: \(error.localizedDescription)") }
                    NSApp.terminate(nil)
                }
            } else { NSApp.terminate(nil) }
        }
    }
}
