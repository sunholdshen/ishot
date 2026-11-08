import AppKit
import Carbon

struct Shortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String
    var label: String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value + key.uppercased()
    }
    static let defaults = [
        Shortcut(keyCode: 20, modifiers: UInt32(cmdKey | shiftKey), key: "3"),
        Shortcut(keyCode: 21, modifiers: UInt32(cmdKey | shiftKey), key: "4"),
        Shortcut(keyCode: 35, modifiers: UInt32(cmdKey | shiftKey | optionKey), key: "P")
    ].enumerated().map { index, shortcut in
        // Avoid the built-in screenshot shortcuts by adding Option.
        Shortcut(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers | UInt32(optionKey), key: shortcut.key)
    }
}

final class HotKeyManager {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private(set) var shortcuts: [Shortcut]
    var onAction: ((Int) -> Void)?
    init() {
        if let data = UserDefaults.standard.data(forKey: "shortcuts"), let values = try? JSONDecoder().decode([Shortcut].self, from: data), values.count == 3 { shortcuts = values }
        else { shortcuts = Shortcut.defaults }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer -> OSStatus in
            guard let event, let pointer else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == 0x49534854 else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(pointer).takeUnretainedValue()
            DispatchQueue.main.async { manager.onAction?(Int(id.id)) }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    deinit { unregister(); if let handler { RemoveEventHandler(handler) } }
    func unregister() { refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll() }
    private func register(_ values: [Shortcut]) -> Bool {
        for (index, value) in values.enumerated() {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(value.keyCode, value.modifiers, EventHotKeyID(signature: 0x49534854, id: UInt32(index)), GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else { unregister(); return false }
            refs.append(ref)
        }
        return true
    }
    @discardableResult func apply(_ values: [Shortcut], persist: Bool = true) -> Bool {
        guard values.count == 3, Set(values.map { "\($0.keyCode)-\($0.modifiers)" }).count == 3 else { return false }
        let previous = shortcuts
        unregister()
        guard register(values) else { _ = register(previous); return false }
        shortcuts = values
        if persist, let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: "shortcuts") }
        return true
    }
}

final class ShortcutButton: NSButton {
    var shortcut: Shortcut { didSet { title = shortcut.label } }
    var onRecord: ((Shortcut) -> Bool)?
    private var recording = false
    override var acceptsFirstResponder: Bool { true }
    init(shortcut: Shortcut) {
        self.shortcut = shortcut
        super.init(frame: CGRect(x: 0, y: 0, width: 170, height: 30))
        title = shortcut.label; bezelStyle = .rounded; target = self; action = #selector(beginRecording)
        toolTip = "点击后按下新快捷键；Esc 取消"
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func beginRecording() { recording = true; title = "请按快捷键…"; window?.makeFirstResponder(self) }
    override func resignFirstResponder() -> Bool { recording = false; title = shortcut.label; return super.resignFirstResponder() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording { keyDown(with: event); return true }; return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { recording = false; title = shortcut.label; return }
        let flags = event.modifierFlags
        guard flags.contains(.command) || flags.contains(.control), let key = event.charactersIgnoringModifiers, key.count == 1, key.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
            title = "需 ⌘ / ⌃ + 字母或数字"; return
        }
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        let candidate = Shortcut(keyCode: UInt32(event.keyCode), modifiers: mods, key: key)
        recording = false
        if onRecord?(candidate) == true { shortcut = candidate } else { title = shortcut.label; showError("快捷键重复或已被占用，请选择其他组合。") }
    }
}
