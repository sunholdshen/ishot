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
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false; panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size), image: image)
        view.canInteract = { [weak self, weak view] in
            guard let self else { return false }
            return !self.panels.contains { panel in
                guard let other = panel.contentView as? SelectionView, other !== view else { return false }
                return other.isWaitingForSecondPoint
            }
        }
        view.beginInteraction = { [weak self, weak view] in
            self?.panels.forEach { panel in
                if let other = panel.contentView as? SelectionView, other !== view { other.resetSelection() }
            }
        }
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
    private var model: SelectionModel
    var selection: CGRect { model.rect }
    var isWaitingForSecondPoint: Bool { model.anchor != nil }
    var isSelectionReady: Bool { model.isReady }
    var isToolbarVisible: Bool { !toolbar.isHidden }
    private var pointer: CGPoint?
    private var optionDown = false
    private let toolbar = NSStackView()
    private var tracking: NSTrackingArea?
    var complete: ((CGRect, CaptureAction) -> Void)?
    var cancel: (() -> Void)?
    var canInteract: (() -> Bool)?
    var beginInteraction: (() -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(frame: CGRect, image: CGImage, method: SelectionMethod = .saved()) {
        self.image = image; model = SelectionModel(size: frame.size, method: method)
        super.init(frame: frame)
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
        tracking = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(tracking!); super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) {
        if canInteract?() != false { window?.makeKey(); window?.makeFirstResponder(self) }
        mouseMoved(with: event)
    }
    override func mouseExited(with event: NSEvent) { pointer = nil; needsDisplay = true }
    override func mouseMoved(with event: NSEvent) {
        pointer = point(event); optionDown = event.modifierFlags.contains(.option)
        if canInteract?() != false { model.hover(pointer!) }
        needsDisplay = true
    }
    override func flagsChanged(with event: NSEvent) { optionDown = event.modifierFlags.contains(.option); needsDisplay = true }
    func resetSelection() { model.reset(); toolbar.isHidden = true; pointer = nil; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: image, size: .zero).draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let shade = NSBezierPath(rect: bounds)
        if !selection.isEmpty { shade.appendRect(selection) }; shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.42).setFill(); shade.fill()
        if !selection.isEmpty {
            NSColor.controlAccentColor.setStroke(); let path = NSBezierPath(rect: selection); path.lineWidth = 1.5; path.stroke()
            if model.anchor == nil {
                NSColor.white.setFill(); for p in model.corners { CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6).fill() }
            }
            let rect = Geometry.pixelRect(selection, viewSize: bounds.size, pixels: CGSize(width: image.width, height: image.height))
            let label = "\(Int(rect.width)) × \(Int(rect.height)) px"
            (label as NSString).draw(at: CGPoint(x: selection.minX + 6, y: max(6, selection.minY - 25)), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white, .backgroundColor: NSColor.black.withAlphaComponent(0.6)])
        }
        if let anchor = model.anchor {
            let dot = NSBezierPath(ovalIn: CGRect(x: anchor.x - 5, y: anchor.y - 5, width: 10, height: 10))
            NSColor.controlAccentColor.setFill(); dot.fill(); NSColor.white.setStroke(); dot.lineWidth = 2; dot.stroke()
        }
        drawHint()
        if let pointer, !model.isReady, canInteract?() != false { drawMagnifier(at: pointer) }
    }
    private func drawHint() {
        let hint: String
        if canInteract?() == false { hint = "请回到第一个角所在的屏幕完成框选 · Esc 取消" }
        else if model.anchor != nil { hint = "单击另一个角 · 可松开按键、抬手移动 · Delete 重选 · Esc 取消" }
        else if model.isReady { hint = "拖动调整选区 · P 钉住 · Enter 批注 · Esc 取消" }
        else if model.method == .twoPoint || optionDown { hint = "双点框选：单击第一个角，再单击另一个角 · Esc 取消" }
        else { hint = "拖动框选 · ⌥ + 单击启用双点框选 · Esc 取消" }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white]
        let textSize = (hint as NSString).size(withAttributes: attributes)
        let box = CGRect(x: max(8, (bounds.width - textSize.width - 28) / 2), y: 16, width: min(bounds.width - 16, textSize.width + 28), height: 34)
        NSColor.black.withAlphaComponent(0.8).setFill(); NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
        (hint as NSString).draw(in: box.insetBy(dx: 14, dy: 8), withAttributes: attributes)
    }
    private func drawMagnifier(at point: CGPoint) {
        let pixels = CGSize(width: image.width, height: image.height)
        let sample = MagnifierGeometry.sample(at: point, viewSize: bounds.size, pixels: pixels)
        guard let patch = image.cropping(to: sample) else { return }
        let width: CGFloat = 144, height: CGFloat = 174
        let preferredX = point.x + width + 24 < bounds.width ? point.x + 24 : point.x - width - 24
        let preferredY = point.y + height + 24 < bounds.height ? point.y + 24 : point.y - height - 24
        let card = CGRect(x: min(max(8, preferredX), max(8, bounds.width - width - 8)), y: min(max(8, preferredY), max(8, bounds.height - height - 8)), width: width, height: height)
        NSColor(calibratedWhite: 0.08, alpha: 0.96).setFill(); NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10).fill()
        let title = model.anchor == nil ? "精确定位" : "选择另一个角"
        (title as NSString).draw(at: CGPoint(x: card.minX + 12, y: card.minY + 8), withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white])
        let lens = CGRect(x: card.minX + 12, y: card.minY + 30, width: 120, height: 120)
        NSGraphicsContext.saveGraphicsState()
        NSImage(cgImage: patch, size: .zero).draw(in: lens, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
        let px = min(max(0, floor(point.x * pixels.width / bounds.width)), pixels.width - 1)
        let py = min(max(0, floor(point.y * pixels.height / bounds.height)), pixels.height - 1)
        let cx = lens.minX + (px - sample.minX + 0.5) / sample.width * lens.width
        let cy = lens.minY + (py - sample.minY + 0.5) / sample.height * lens.height
        let cross = NSBezierPath(); cross.move(to: CGPoint(x: lens.minX, y: cy)); cross.line(to: CGPoint(x: lens.maxX, y: cy)); cross.move(to: CGPoint(x: cx, y: lens.minY)); cross.line(to: CGPoint(x: cx, y: lens.maxY))
        NSColor.black.withAlphaComponent(0.8).setStroke(); cross.lineWidth = 3; cross.stroke()
        NSColor.white.setStroke(); cross.lineWidth = 1; cross.stroke()
        NSGraphicsContext.restoreGraphicsState()
        ("x \(Int(px))  y \(Int(py))" as NSString).draw(at: CGPoint(x: card.minX + 12, y: card.minY + 156), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor.white])
    }
    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(0, p.x), bounds.width), y: min(max(0, p.y), bounds.height))
    }
    override func mouseDown(with event: NSEvent) {
        guard canInteract?() != false else { NSSound.beep(); needsDisplay = true; return }
        window?.makeKey(); window?.makeFirstResponder(self)
        beginInteraction?(); pointer = point(event); optionDown = event.modifierFlags.contains(.option)
        model.press(pointer!, option: optionDown); refresh()
    }
    override func mouseDragged(with event: NSEvent) {
        guard canInteract?() != false else { return }
        pointer = point(event); model.drag(pointer!); refresh()
    }
    override func mouseUp(with event: NSEvent) {
        guard canInteract?() != false else { return }
        pointer = point(event); model.release(pointer!); refresh()
    }
    private func refresh() {
        toolbar.isHidden = !model.isReady
        if model.isReady {
            let width = min(bounds.width - 16, toolbar.fittingSize.width)
            let height: CGFloat = 46
            let y = selection.maxY + height + 12 <= bounds.height ? selection.maxY + 8 : max(8, selection.minY - height - 8)
            toolbar.frame = CGRect(x: min(max(8, selection.maxX - width), bounds.width - width - 8), y: y, width: width, height: height)
        }
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel?(); return }
        if event.keyCode == 51 || event.keyCode == 117 {
            if model.anchor != nil { model.reset(); refresh() }; return
        }
        guard model.isReady else { return }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "p": pin()
        case "c": copySelection()
        case "s": saveSelection()
        case "\r": edit()
        default: break
        }
    }
    private func finish(_ action: CaptureAction) { guard model.isReady else { return }; complete?(selection, action) }
    @objc private func edit() { finish(.edit) }
    @objc private func copySelection() { finish(.copy) }
    @objc private func saveSelection() { finish(.save) }
    @objc private func pin() { finish(.pin) }
    @objc private func cancelSelection() { cancel?() }
}
