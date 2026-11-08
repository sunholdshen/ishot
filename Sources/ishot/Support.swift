import AppKit
import IShotCore
import UniformTypeIdentifiers

func actionButton(_ title: String, symbol: String? = nil, target: AnyObject?, action: Selector) -> NSButton {
    let button = NSButton(title: title, target: target, action: action)
    button.bezelStyle = .rounded
    if let symbol { button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); button.imagePosition = .imageLeading }
    return button
}

func showError(_ message: String) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert(); alert.messageText = "ishot"; alert.informativeText = message
    alert.alertStyle = .warning; alert.addButton(withTitle: "好"); alert.runModal()
}

func copyImage(_ image: CGImage) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects([NSImage(cgImage: image, size: .zero)])
}

func saveImage(_ image: CGImage, parent: NSWindow? = nil) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.canCreateDirectories = true
    let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    panel.nameFieldStringValue = "ishot_\(formatter.string(from: Date())).png"
    if let path = UserDefaults.standard.string(forKey: "saveDirectory") { panel.directoryURL = URL(fileURLWithPath: path) }
    let write: (NSApplication.ModalResponse) -> Void = { response in
        guard response == .OK, let url = panel.url else { return }
        do {
            guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw NSError(domain: "ishot", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法编码 PNG 图片。"])
            }
            try data.write(to: url, options: .atomic)
            UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: "saveDirectory")
        } catch { showError("保存失败：\(error.localizedDescription)") }
    }
    NSApp.activate(ignoringOtherApps: true)
    if let parent { panel.beginSheetModal(for: parent, completionHandler: write) }
    else { write(panel.runModal()) }
}

class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

func makeDemoImage() -> CGImage {
    let size = CGSize(width: 1000, height: 640)
    let context = CGContext(data: nil, width: 1000, height: 640, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor(calibratedRed: 0.09, green: 0.12, blue: 0.2, alpha: 1).cgColor)
    context.fill(CGRect(origin: .zero, size: size))
    context.setFillColor(NSColor(calibratedRed: 0.37, green: 0.87, blue: 0.72, alpha: 1).cgColor)
    context.fill(CGRect(x: 60, y: 540, width: 48, height: 8))
    context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    ("把灵感，钉在眼前。" as NSString).draw(at: CGPoint(x: 60, y: 130), withAttributes: [.font: NSFont.systemFont(ofSize: 62, weight: .semibold), .foregroundColor: NSColor.white])
    ("截图  /  批注  /  随手贴在屏幕上" as NSString).draw(at: CGPoint(x: 64, y: 240), withAttributes: [.font: NSFont.systemFont(ofSize: 27), .foregroundColor: NSColor.lightGray])
    ("ishot · 本地处理 · 自由摆放" as NSString).draw(at: CGPoint(x: 64, y: 520), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 19, weight: .medium), .foregroundColor: NSColor.white])
    NSGraphicsContext.restoreGraphicsState()
    return context.makeImage()!
}
