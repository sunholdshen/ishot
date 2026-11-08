import AppKit
import ScreenCaptureKit
import IShotCore

@MainActor final class CaptureCoordinator {
    private var panels: [NSPanel] = []
    private var capturing = false
    private var keyboardMonitor: Any?
    var onImage: ((CGImage, Bool) -> Void)?
    var onFailure: ((Error) -> Void)?
    var isSelecting: Bool { !panels.isEmpty }
    func start(fullscreen: Bool = false) {
        guard !capturing, panels.isEmpty else { return }
        capturing = true
        Task {
            defer { capturing = false }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let mouseScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
                var frames: [(NSScreen, CGImage)] = []
                for screen in NSScreen.screens {
                    if fullscreen && screen != mouseScreen { continue }
                    guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                          let display = content.displays.first(where: { $0.displayID == id }) else { continue }
                    let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                    let config = SCStreamConfiguration()
                    config.width = Int(screen.frame.width * screen.backingScaleFactor)
                    config.height = Int(screen.frame.height * screen.backingScaleFactor)
                    config.showsCursor = false; config.captureResolution = .best
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    frames.append((screen, image))
                }
                guard !frames.isEmpty else { throw NSError(domain: "ishot", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有找到可截图的显示器。请连接显示器后重试。"]) }
                if fullscreen { onImage?(frames[0].1, false); return }
                for (screen, image) in frames { createOverlay(screen: screen, image: image) }
                NSApp.activate(ignoringOtherApps: true)
                for panel in panels { panel.orderFrontRegardless() }
                if let panel = panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) { panel.makeKey(); panel.makeFirstResponder(panel.contentView) }
                keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }
                    if event.keyCode == 53 { self.cancel(); return nil }
                    return event
                }
            } catch {
                cancel()
                if let onFailure { onFailure(error); return }
                let alert = NSAlert(); alert.messageText = "无法截取屏幕"
                alert.informativeText = "首次使用请允许 ishot 录制屏幕。若已授权仍失败，请退出并重新打开 ishot。\n\n\(error.localizedDescription)"
                alert.addButton(withTitle: "打开权限设置"); alert.addButton(withTitle: "取消")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn { Self.openPermissions() }
            }
        }
    }
    static func openPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    private func createOverlay(screen: NSScreen, image: CGImage) {
        let panel = KeyPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .screenSaver; panel.isOpaque = true; panel.backgroundColor = .black; panel.hasShadow = false
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size), image: image)
        view.complete = { [weak self] rect, action in
            guard let self else { return }
            let pixels = Geometry.pixelRect(rect, viewSize: screen.frame.size, pixels: CGSize(width: image.width, height: image.height))
            guard pixels.width >= 2, pixels.height >= 2, let cropped = image.cropping(to: pixels) else { return }
            self.cancel()
            // Leave the screen-covering panels before presenting normal windows or save dialogs.
            DispatchQueue.main.async {
                switch action {
                case .pin: self.onImage?(cropped, true)
                case .copy: copyImage(cropped)
                case .save: saveImage(cropped)
                case .edit: self.onImage?(cropped, false)
                }
            }
        }
        view.cancel = { [weak self] in self?.cancel() }
        panel.contentView = view; panels.append(panel)
    }
    func cancel() {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor); self.keyboardMonitor = nil }
        panels.forEach { $0.orderOut(nil); $0.close() }; panels.removeAll()
    }
}

enum CaptureAction { case edit, pin, copy, save }
final class SelectionView: NSView {
    let image: CGImage
    var selection = CGRect.zero
    private var start = CGPoint.zero
    private var original = CGRect.zero
    private var mode = 0 // 0 new selection, 1 move, 2 corner resize
    private var fixedCorner = CGPoint.zero
    private let toolbar = NSStackView()
    private var tracking: NSTrackingArea?
    var complete: ((CGRect, CaptureAction) -> Void)?
    var cancel: (() -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(frame: CGRect, image: CGImage) {
        self.image = image; super.init(frame: frame)
        toolbar.orientation = .horizontal; toolbar.spacing = 6; toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        toolbar.wantsLayer = true; toolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor; toolbar.layer?.cornerRadius = 10
        for (title, symbol, action) in [("批注 ↩", "pencil.tip", #selector(edit)), ("复制 C", "doc.on.doc", #selector(copySelection)), ("保存 S", "square.and.arrow.down", #selector(saveSelection)), ("钉住 P", "pin.fill", #selector(pin)), ("取消", "xmark", #selector(cancelSelection))] {
            toolbar.addArrangedSubview(actionButton(title, symbol: symbol, target: self, action: action))
        }
        addSubview(toolbar); toolbar.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(tracking!); super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { window?.makeKey(); window?.makeFirstResponder(self) }
    private var corners: [CGPoint] { [CGPoint(x: selection.minX, y: selection.minY), CGPoint(x: selection.maxX, y: selection.minY), CGPoint(x: selection.minX, y: selection.maxY), CGPoint(x: selection.maxX, y: selection.maxY)] }
    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: image, size: .zero).draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let shade = NSBezierPath(rect: bounds)
        if !selection.isEmpty { shade.appendRect(selection) }; shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.42).setFill(); shade.fill()
        if !selection.isEmpty {
            NSColor.controlAccentColor.setStroke(); let path = NSBezierPath(rect: selection); path.lineWidth = 1.5; path.stroke()
            NSColor.white.setFill(); for p in corners { CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6).fill() }
            let rect = Geometry.pixelRect(selection, viewSize: bounds.size, pixels: CGSize(width: image.width, height: image.height))
            let label = "\(Int(rect.width)) × \(Int(rect.height)) px"
            (label as NSString).draw(at: CGPoint(x: selection.minX + 6, y: max(6, selection.minY - 25)), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white, .backgroundColor: NSColor.black.withAlphaComponent(0.6)])
        } else {
            let hint = "拖动选取区域 · Esc 取消 · 每次可截取一块显示器中的区域"
            (hint as NSString).draw(at: CGPoint(x: max(20, bounds.midX - 210), y: 40), withAttributes: [.font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.white])
        }
    }
    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(0, p.x), bounds.width), y: min(max(0, p.y), bounds.height))
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey(); window?.makeFirstResponder(self)
        start = point(event); original = selection; toolbar.isHidden = true
        if !selection.isEmpty, let index = corners.firstIndex(where: { hypot($0.x - start.x, $0.y - start.y) <= 12 }) {
            mode = 2; fixedCorner = corners[3 - index]
        } else if selection.contains(start) { mode = 1 }
        else { mode = 0; selection = .zero }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        let p = point(event)
        switch mode {
        case 1: selection = Geometry.moved(original, by: CGPoint(x: p.x - start.x, y: p.y - start.y), within: bounds)
        case 2: selection = Geometry.rect(from: fixedCorner, to: p)
        default: selection = Geometry.rect(from: start, to: p)
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if selection.width >= 2, selection.height >= 2 {
            toolbar.isHidden = false
            let width = min(bounds.width - 16, toolbar.fittingSize.width)
            let height: CGFloat = 46
            let y = selection.maxY + height + 12 <= bounds.height ? selection.maxY + 8 : max(8, selection.minY - height - 8)
            toolbar.frame = CGRect(x: min(max(8, selection.maxX - width), bounds.width - width - 8), y: y, width: width, height: height)
        }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel?(); return }
        guard !selection.isEmpty else { return }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "p": pin()
        case "c": copySelection()
        case "s": saveSelection()
        case "\r": edit()
        default: break
        }
    }
    @objc private func edit() { complete?(selection, .edit) }
    @objc private func copySelection() { complete?(selection, .copy) }
    @objc private func saveSelection() { complete?(selection, .save) }
    @objc private func pin() { complete?(selection, .pin) }
    @objc private func cancelSelection() { cancel?() }
}
