import AppKit
import IShotCore

final class PinView: NSView {
    weak var owner: PinController?
    private var tracking: NSTrackingArea?
    private let closeButton = NSButton()
    private let editButton = NSButton()
    private let menuButton = NSButton()
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        for (button, icon, title, action) in [(closeButton, "xmark", "关闭贴图", #selector(closePin)), (editButton, "pencil", "继续批注", #selector(editPin)), (menuButton, "ellipsis", "贴图选项", #selector(showMenu))] {
            button.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
            button.toolTip = title; button.bezelStyle = .regularSquare; button.isBordered = false
            button.wantsLayer = true; button.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor; button.layer?.cornerRadius = 6
            button.target = self; button.action = action; button.isHidden = true; addSubview(button)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        closeButton.frame = CGRect(x: 7, y: 7, width: 27, height: 25)
        editButton.frame = CGRect(x: 39, y: 7, width: 27, height: 25)
        menuButton.frame = CGRect(x: 71, y: 7, width: 27, height: 25)
    }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!); super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { [closeButton, editButton, menuButton].forEach { $0.isHidden = false } }
    override func mouseExited(with event: NSEvent) { [closeButton, editButton, menuButton].forEach { $0.isHidden = true } }
    override func draw(_ dirtyRect: NSRect) {
        guard let owner else { return }
        NSImage(cgImage: owner.image, size: .zero).draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        (owner.locked ? NSColor.systemOrange : NSColor.white.withAlphaComponent(0.5)).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)); border.lineWidth = 1; border.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { owner?.resetSize(); return }
        if owner?.locked == false { window?.performDrag(with: event) }
    }
    override func scrollWheel(with event: NSEvent) {
        guard let owner else { return }
        if event.modifierFlags.contains(.option) { owner.setOpacity((window?.alphaValue ?? 1) + event.scrollingDeltaY * 0.01) }
        else { owner.zoom(by: exp(event.scrollingDeltaY * 0.008)) }
    }
    override func magnify(with event: NSEvent) { owner?.zoom(by: 1 + event.magnification) }
    override func menu(for event: NSEvent) -> NSMenu? { owner?.makeMenu() }
    @objc private func closePin() { owner?.close() }
    @objc private func editPin() { owner?.edit() }
    @objc private func showMenu() {
        guard let menu = owner?.makeMenu() else { return }
        menu.popUp(positioning: nil, at: CGPoint(x: menuButton.frame.minX, y: menuButton.frame.maxY), in: self)
    }
}

final class PinController: NSWindowController, NSWindowDelegate {
    var image: CGImage
    private let originalScale: CGFloat
    var locked = false
    var onClose: (() -> Void)?
    var onEdit: ((CGImage, @escaping (CGImage) -> Void) -> Void)?
    init(image: CGImage) {
        self.image = image
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        originalScale = screen.backingScaleFactor
        let naturalSize = CGSize(width: CGFloat(image.width) / originalScale, height: CGFloat(image.height) / originalScale)
        let size = Geometry.fittedSize(naturalSize, within: CGSize(width: screen.visibleFrame.width * 0.7, height: screen.visibleFrame.height * 0.7))
        let window = KeyPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .floating; window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.isReleasedWhenClosed = false; window.hidesOnDeactivate = false; window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.title = "ishot · 贴图"
        super.init(window: window)
        let view = PinView(frame: CGRect(origin: .zero, size: size)); view.owner = self
        window.contentView = view; window.delegate = self
        let origin = CGPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2)
        window.setFrameOrigin(origin)
        if UserDefaults.standard.object(forKey: "pinOpacity") != nil { setOpacity(CGFloat(UserDefaults.standard.double(forKey: "pinOpacity"))) }
    }
    required init?(coder: NSCoder) { fatalError() }
    func present() { window?.orderFrontRegardless() }
    func windowWillClose(_ notification: Notification) { onClose?() }
    func zoom(by factor: CGFloat) {
        guard !locked, let window, factor.isFinite, factor > 0 else { return }
        let old = window.frame
        let screen = window.screen ?? NSScreen.main!
        let proposed = old.width * factor
        let width = min(max(proposed, 100), screen.visibleFrame.width * 1.5)
        let height = width * CGFloat(image.height) / CGFloat(image.width)
        guard height <= screen.visibleFrame.height * 1.5 else { return }
        window.setFrame(CGRect(x: old.midX - width / 2, y: old.midY - height / 2, width: width, height: height), display: true)
    }
    @objc func resetSize() {
        guard !locked, let window else { return }
        let desired = CGFloat(image.width) / originalScale
        zoom(by: desired / window.frame.width)
    }
    func setOpacity(_ value: CGFloat) { window?.alphaValue = min(1, max(0.2, value)) }
    @objc func edit() {
        onEdit?(image, { [weak self] image in
            guard let self else { return }
            let old = self.image; self.image = image
            if old.width != image.width || old.height != image.height, let window = self.window {
                let width = min(window.frame.width, CGFloat(image.width) / self.originalScale)
                window.setContentSize(CGSize(width: width, height: width * CGFloat(image.height) / CGFloat(image.width)))
            }
            self.window?.contentView?.needsDisplay = true
        })
    }
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item); return item
        }
        _ = add("继续批注…", #selector(edit))
        _ = add("复制图片", #selector(copy(_:)))
        _ = add("保存 PNG…", #selector(save(_:)))
        menu.addItem(.separator())
        _ = add("恢复原始尺寸（双击）", #selector(resetSize))
        let lock = add("锁定位置和大小", #selector(toggleLock)); lock.state = locked ? .on : .off
        let opacity = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for percent in [100, 80, 60, 40, 20] {
            let item = NSMenuItem(title: "\(percent)%", action: #selector(changeOpacity(_:)), keyEquivalent: ""); item.target = self; item.tag = percent
            item.state = abs((window?.alphaValue ?? 1) - CGFloat(percent) / 100) < 0.01 ? .on : .off; sub.addItem(item)
        }
        opacity.submenu = sub; menu.addItem(opacity)
        menu.addItem(.separator()); _ = add("关闭贴图", #selector(closePin))
        return menu
    }
    @objc func copy(_ sender: Any?) { copyImage(image) }
    @objc func save(_ sender: Any?) { saveImage(image) }
    @objc private func toggleLock() { locked.toggle(); window?.contentView?.needsDisplay = true }
    @objc private func changeOpacity(_ sender: NSMenuItem) { setOpacity(CGFloat(sender.tag) / 100) }
    @objc private func closePin() { close() }
}
