import AppKit
import IShotCore

final class CanvasView: NSView {
    let imageDocument: ImageDocument
    var tool: MarkTool = .arrow
    var ink: NSColor = .systemRed
    var strokeWidth: CGFloat = 4
    var draft: Annotation?
    var changed: (() -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(imageDocument: ImageDocument) { self.imageDocument = imageDocument; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    private var scale: CGFloat { bounds.width / imageDocument.size.width }
    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(0, p.x / scale), imageDocument.size.width), y: min(max(0, p.y / scale), imageDocument.size.height))
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState(); context.scaleBy(x: scale, y: scale)
        imageDocument.draw(in: context, draft: draft?.tool == .crop ? nil : draft)
        if let draft, draft.tool == .crop, let first = draft.points.first, let last = draft.points.last {
            let rect = Geometry.rect(from: first, to: last)
            NSColor.controlAccentColor.withAlphaComponent(0.2).setFill(); rect.fill()
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: rect); path.lineWidth = 2 / scale; path.setLineDash([6 / scale, 4 / scale], count: 2, phase: 0); path.stroke()
        }
        context.restoreGState()
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = point(event)
        if tool == .text {
            let alert = NSAlert(); alert.messageText = "添加文字"; alert.addButton(withTitle: "添加"); alert.addButton(withTitle: "取消")
            let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 320, height: 28)); field.placeholderString = "输入批注内容"
            alert.accessoryView = field; alert.window.initialFirstResponder = field
            if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty {
                imageDocument.add(Annotation(tool: .text, points: [p], color: ink, width: strokeWidth, text: field.stringValue)); changed?(); needsDisplay = true
            }
            return
        }
        draft = Annotation(tool: tool, points: [p, p], color: ink, width: strokeWidth)
    }
    override func mouseDragged(with event: NSEvent) {
        guard draft != nil else { return }
        if tool == .pen { draft?.points.append(point(event)) }
        else { draft?.points[1] = point(event) }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard var mark = draft else { return }
        if mark.tool != .pen { mark.points[1] = point(event) }
        draft = nil
        if mark.tool == .crop { imageDocument.crop(to: Geometry.rect(from: mark.points[0], to: mark.points[1])) }
        else if mark.tool == .pen || hypot(mark.points[0].x - mark.points.last!.x, mark.points[0].y - mark.points.last!.y) > 2 { imageDocument.add(mark) }
        changed?(); needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { draft = nil; needsDisplay = true }
        else { super.keyDown(with: event) }
    }
}

final class EditorController: NSWindowController, NSWindowDelegate {
    let imageDocument: ImageDocument
    let canvas: CanvasView
    let scroll = NSScrollView()
    let undoButton = NSButton(title: "", target: nil, action: nil)
    let redoButton = NSButton(title: "", target: nil, action: nil)
    private let toolPicker = NSSegmentedControl()
    private let colorWell = NSColorWell()
    private let widthPicker = NSPopUpButton()
    private let dimensions = NSTextField(labelWithString: "")
    var onPin: ((CGImage) -> Void)?
    var onClose: (() -> Void)?
    var onApply: ((CGImage) -> Void)?
    init(image: CGImage, apply: ((CGImage) -> Void)? = nil) {
        imageDocument = ImageDocument(image: image); canvas = CanvasView(imageDocument: imageDocument); onApply = apply
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1060, height: 750), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "ishot · 批注"; window.minSize = CGSize(width: 900, height: 460); window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self; window.center()
        buildUI()
        canvas.changed = { [weak self] in self?.refresh() }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func buildUI() {
        guard let root = window?.contentView else { return }
        root.wantsLayer = true; root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let controls = NSStackView(); controls.orientation = .horizontal; controls.spacing = 10
        toolPicker.segmentCount = MarkTool.allCases.count
        for (index, tool) in MarkTool.allCases.enumerated() {
            toolPicker.setImage(NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.rawValue), forSegment: index)
            toolPicker.setToolTip(tool.rawValue, forSegment: index); toolPicker.setWidth(38, forSegment: index)
        }
        toolPicker.selectedSegment = 2; toolPicker.target = self; toolPicker.action = #selector(changeTool)
        colorWell.color = .systemRed; colorWell.target = self; colorWell.action = #selector(changeInk)
        colorWell.setFrameSize(CGSize(width: 36, height: 28))
        widthPicker.addItems(withTitles: ["细 · 2", "中 · 4", "粗 · 8", "特粗 · 12"]); widthPicker.selectItem(at: 1)
        widthPicker.target = self; widthPicker.action = #selector(changeWidth)
        undoButton.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "撤销"); undoButton.bezelStyle = .rounded; undoButton.target = self; undoButton.action = #selector(undo(_:)); undoButton.toolTip = "撤销 ⌘Z"
        redoButton.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "重做"); redoButton.bezelStyle = .rounded; redoButton.target = self; redoButton.action = #selector(redo(_:)); redoButton.toolTip = "重做 ⇧⌘Z"
        [toolPicker, colorWell, widthPicker, undoButton, redoButton].forEach { controls.addArrangedSubview($0) }
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal); controls.addArrangedSubview(spacer)
        let copy = actionButton("复制", symbol: "doc.on.doc", target: self, action: #selector(copy(_:))); copy.keyEquivalent = "c"; copy.keyEquivalentModifierMask = .command
        let save = actionButton("保存", symbol: "square.and.arrow.down", target: self, action: #selector(save(_:))); save.keyEquivalent = "s"; save.keyEquivalentModifierMask = .command
        let pin = actionButton(onApply == nil ? "钉住" : "更新贴图", symbol: "pin.fill", target: self, action: #selector(pinImage)); pin.keyEquivalent = "p"; pin.keyEquivalentModifierMask = .command
        [copy, save, pin].forEach { controls.addArrangedSubview($0) }
        scroll.drawsBackground = true; scroll.backgroundColor = .underPageBackgroundColor
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.documentView = canvas
        dimensions.font = .monospacedSystemFont(ofSize: 11, weight: .regular); dimensions.textColor = .secondaryLabelColor
        let tip = NSTextField(labelWithString: "拖动绘制 · 裁剪后可撤销 · PNG 保留原始像素"); tip.font = .systemFont(ofSize: 11); tip.textColor = .secondaryLabelColor
        let footer = NSStackView(views: [dimensions, tip]); footer.distribution = .equalSpacing
        for view in [controls, scroll, footer] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: root.topAnchor, constant: 12), controls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16), controls.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16), controls.heightAnchor.constraint(equalToConstant: 34),
            scroll.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 12), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -10),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16), footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16), footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10)
        ])
    }
    func refresh() {
        let available = scroll.contentSize
        let size = Geometry.fittedSize(imageDocument.size, within: CGSize(width: max(400, available.width), height: max(280, available.height)))
        canvas.setFrameSize(size); canvas.needsDisplay = true
        dimensions.stringValue = "\(imageDocument.image.width) × \(imageDocument.image.height) px"
        undoButton.isEnabled = imageDocument.canUndo; redoButton.isEnabled = imageDocument.canRedo
    }
    func windowDidResize(_ notification: Notification) { refresh() }
    func windowWillClose(_ notification: Notification) { onClose?() }
    func present() { showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil); window?.layoutIfNeeded(); refresh() }
    @objc private func changeTool() { canvas.tool = MarkTool.allCases[toolPicker.selectedSegment] }
    @objc private func changeInk() { canvas.ink = colorWell.color }
    @objc private func changeWidth() { canvas.strokeWidth = [2, 4, 8, 12][widthPicker.indexOfSelectedItem] }
    @objc func undo(_ sender: Any?) { imageDocument.undo(); refresh() }
    @objc func redo(_ sender: Any?) { imageDocument.redo(); refresh() }
    @objc func copy(_ sender: Any?) { if let image = imageDocument.renderedImage() { copyImage(image) } }
    @objc func save(_ sender: Any?) { if let image = imageDocument.renderedImage() { saveImage(image, parent: window) } }
    @objc private func pinImage() {
        guard let image = imageDocument.renderedImage() else { return }
        if let onApply { onApply(image) } else { onPin?(image) }
        close()
    }
}
