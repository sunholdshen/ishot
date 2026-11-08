import AppKit
import ServiceManagement

final class SettingsController: NSWindowController {
    private let hotKeys: HotKeyManager
    private let directory = NSTextField(labelWithString: "")
    private let login = NSButton(checkboxWithTitle: "登录 Mac 时启动 ishot", target: nil, action: nil)
    private let opacity = NSSlider(value: 100, minValue: 20, maxValue: 100, target: nil, action: nil)
    private var recorders: [ShortcutButton] = []
    init(hotKeys: HotKeyManager) {
        self.hotKeys = hotKeys
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 570, height: 390), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ishot · 设置"; window.isReleasedWhenClosed = false
        super.init(window: window); window.center()
        let tabs = NSTabView(frame: CGRect(x: 20, y: 20, width: 530, height: 350)); tabs.autoresizingMask = [.width, .height]; window.contentView?.addSubview(tabs)
        func tab(_ title: String, views: [NSView]) {
            let item = NSTabViewItem(identifier: title); item.label = title
            let container = NSView()
            let stack = NSStackView(views: views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18; stack.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(stack)
            NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 26), stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24)])
            item.view = container; tabs.addTabViewItem(item)
        }
        login.target = self; login.action = #selector(toggleLogin)
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        tab("通用", views: [label("轻量常驻，随时截图。", bold: true), login, label("关闭窗口后，ishot 仍会留在菜单栏。"), actionButton("屏幕录制权限…", symbol: "lock.shield", target: self, action: #selector(permissions))])
        var rows: [NSView] = [label("点击快捷键后，按下新的组合。", bold: true)]
        for (index, title) in ["区域截图", "当前显示器全屏截图", "显示 / 隐藏全部贴图"].enumerated() {
            let recorder = ShortcutButton(shortcut: hotKeys.shortcuts[index]); recorders.append(recorder)
            recorder.onRecord = { [weak self] shortcut in
                guard let self else { return false }
                var values = self.hotKeys.shortcuts; values[index] = shortcut
                return self.hotKeys.apply(values)
            }
            let row = NSStackView(views: [label(title), recorder]); row.spacing = 24; rows.append(row)
        }
        rows.append(label("需包含 ⌘ 或 ⌃；默认截图快捷键还包含 ⌥ 和 ⇧。")); tab("快捷键", views: rows)
        directory.stringValue = UserDefaults.standard.string(forKey: "saveDirectory") ?? "保存时选择目录"; directory.lineBreakMode = .byTruncatingMiddle
        tab("截图", views: [label("PNG · 原始分辨率", bold: true), label("截图不会自动写入磁盘，点击“保存”时再选择文件。"), label("默认保存目录"), directory, actionButton("选择目录…", symbol: "folder", target: self, action: #selector(chooseDirectory))])
        if UserDefaults.standard.object(forKey: "pinOpacity") != nil { opacity.doubleValue = UserDefaults.standard.double(forKey: "pinOpacity") * 100 }
        opacity.target = self; opacity.action = #selector(changeOpacity); opacity.widthAnchor.constraint(equalToConstant: 340).isActive = true
        tab("贴图", views: [label("新贴图默认透明度", bold: true), opacity, label("20% ← → 100%"), label("滚轮 / 双指缩放：调整大小\nOption + 滚轮：调整透明度\n双击：恢复原始尺寸\n右键：锁定、批注、保存和关闭\n贴图跟随桌面空间，位于普通窗口上方。")])
    }
    required init?(coder: NSCoder) { fatalError() }
    private func label(_ text: String, bold: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text); field.font = .systemFont(ofSize: bold ? 16 : 13, weight: bold ? .semibold : .regular); return field
    }
    func present() {
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    @objc private func toggleLogin() {
        do {
            if login.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval {
                showError("请在系统设置 → 通用 → 登录项中允许 ishot 在登录时启动。")
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { showError("无法更改登录项。请先把 ishot 放进 Applications，再重新打开。\n\(error.localizedDescription)") }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
    @objc private func chooseDirectory() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { UserDefaults.standard.set(url.path, forKey: "saveDirectory"); directory.stringValue = url.path }
    }
    @objc private func permissions() { CaptureCoordinator.openPermissions() }
    @objc private func changeOpacity() { UserDefaults.standard.set(opacity.doubleValue / 100, forKey: "pinOpacity") }
}

final class WelcomeController: NSWindowController {
    var onCapture: (() -> Void)?
    var onDemo: (() -> Void)?
    override init(window: NSWindow?) { super.init(window: window) }
    convenience init() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 620, height: 440), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "欢迎使用 ishot"; window.isReleasedWhenClosed = false
        self.init(window: window); window.center()
        let brand = NSTextField(labelWithString: "ishot"); brand.font = .systemFont(ofSize: 18, weight: .bold); brand.textColor = .controlAccentColor
        let title = NSTextField(labelWithString: "把参考，钉在眼前。"); title.font = .systemFont(ofSize: 34, weight: .bold)
        let subtitle = NSTextField(wrappingLabelWithString: "截取屏幕、轻松批注，再把图片放在最需要的位置。\n所有图片只在本机处理。")
        subtitle.font = .systemFont(ofSize: 15); subtitle.textColor = .secondaryLabelColor
        let steps = NSTextField(wrappingLabelWithString: "①  点击开始截图，允许屏幕录制权限\n②  拖动选择区域，按 P 直接钉住\n③  拖动贴图摆放，滚轮缩放，右键查看更多操作")
        steps.font = .systemFont(ofSize: 14)
        let buttons = NSStackView(views: [actionButton("开始截图", symbol: "viewfinder", target: self, action: #selector(capture)), actionButton("试用示例图", symbol: "pin", target: self, action: #selector(demo))]); buttons.spacing = 12
        let note = NSTextField(wrappingLabelWithString: "应用常驻屏幕顶部菜单栏。首次授权后如无法截图，请重新打开。\n退出应用时，未保存的贴图会丢失。")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [brand, title, subtitle, steps, buttons, note]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 22
        stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 40), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -40), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 28)])
    }
    required init?(coder: NSCoder) { fatalError() }
    func present() { showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }
    @objc private func capture() { close(); onCapture?() }
    @objc private func demo() { onDemo?() }
}
