import Foundation
import Carbon
import AppKit

struct ShortcutConfig: Codable {
    var keyCode: UInt32
    var modifiers: UInt32

    var modifierString: String {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        return parts.joined()
    }

    var keyString: String {
        // Map key codes to readable strings
        switch keyCode {
        case UInt32(kVK_ANSI_A): return "A"
        case UInt32(kVK_ANSI_B): return "B"
        case UInt32(kVK_ANSI_C): return "C"
        case UInt32(kVK_ANSI_D): return "D"
        case UInt32(kVK_ANSI_E): return "E"
        case UInt32(kVK_ANSI_F): return "F"
        case UInt32(kVK_ANSI_G): return "G"
        case UInt32(kVK_ANSI_H): return "H"
        case UInt32(kVK_ANSI_I): return "I"
        case UInt32(kVK_ANSI_J): return "J"
        case UInt32(kVK_ANSI_K): return "K"
        case UInt32(kVK_ANSI_L): return "L"
        case UInt32(kVK_ANSI_M): return "M"
        case UInt32(kVK_ANSI_N): return "N"
        case UInt32(kVK_ANSI_O): return "O"
        case UInt32(kVK_ANSI_P): return "P"
        case UInt32(kVK_ANSI_Q): return "Q"
        case UInt32(kVK_ANSI_R): return "R"
        case UInt32(kVK_ANSI_S): return "S"
        case UInt32(kVK_ANSI_T): return "T"
        case UInt32(kVK_ANSI_U): return "U"
        case UInt32(kVK_ANSI_V): return "V"
        case UInt32(kVK_ANSI_W): return "W"
        case UInt32(kVK_ANSI_X): return "X"
        case UInt32(kVK_ANSI_Y): return "Y"
        case UInt32(kVK_ANSI_Z): return "Z"
        case UInt32(kVK_ANSI_0): return "0"
        case UInt32(kVK_ANSI_1): return "1"
        case UInt32(kVK_ANSI_2): return "2"
        case UInt32(kVK_ANSI_3): return "3"
        case UInt32(kVK_ANSI_4): return "4"
        case UInt32(kVK_ANSI_5): return "5"
        case UInt32(kVK_ANSI_6): return "6"
        case UInt32(kVK_ANSI_7): return "7"
        case UInt32(kVK_ANSI_8): return "8"
        case UInt32(kVK_ANSI_9): return "9"
        case UInt32(kVK_Space): return "␣"
        case UInt32(kVK_Return): return "↩"
        case UInt32(kVK_Tab): return "⇥"
        case UInt32(kVK_Delete): return "⌫"
        case UInt32(kVK_Escape): return "⎋"
        case UInt32(kVK_F1): return "F1"
        case UInt32(kVK_F2): return "F2"
        case UInt32(kVK_F3): return "F3"
        case UInt32(kVK_F4): return "F4"
        case UInt32(kVK_F5): return "F5"
        case UInt32(kVK_F6): return "F6"
        case UInt32(kVK_F7): return "F7"
        case UInt32(kVK_F8): return "F8"
        case UInt32(kVK_F9): return "F9"
        case UInt32(kVK_F10): return "F10"
        case UInt32(kVK_F11): return "F11"
        case UInt32(kVK_F12): return "F12"
        case UInt32(kVK_LeftArrow): return "←"
        case UInt32(kVK_RightArrow): return "→"
        case UInt32(kVK_DownArrow): return "↓"
        case UInt32(kVK_UpArrow): return "↑"
        default: return "?"
        }
    }

    var displayString: String {
        return modifierString + keyString
    }
}

class ShortcutManager {
    static var shared: ShortcutManager?

    private var renderHotKeyRef: EventHotKeyRef?
    private var renderInlineHotKeyRef: EventHotKeyRef?
    private var revertHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private let clipboardManager: ClipboardManager

    // Default shortcuts
    static let defaultRenderShortcut = ShortcutConfig(
        keyCode: UInt32(kVK_ANSI_K),
        modifiers: UInt32(cmdKey | optionKey)
    )

    static let defaultRenderInlineShortcut = ShortcutConfig(
        keyCode: UInt32(kVK_ANSI_K),
        modifiers: UInt32(cmdKey | optionKey | controlKey)
    )

    static let defaultRevertShortcut = ShortcutConfig(
        keyCode: UInt32(kVK_ANSI_K),
        modifiers: UInt32(cmdKey | optionKey | shiftKey)
    )

    // UserDefaults keys
    private let renderShortcutKey = "renderShortcut"
    private let renderInlineShortcutKey = "renderInlineShortcut"
    private let revertShortcutKey = "revertShortcut"

    @MainActor
    init() {
        self.clipboardManager = ClipboardManager()
        Self.shared = self
        registerShortcuts()
    }

    deinit {
        Task { [weak self] in
            await MainActor.run {
                self?.unregisterShortcuts()
            }
        }
    }

    // Get current shortcuts from UserDefaults
    func getRenderShortcut() -> ShortcutConfig {
        if let data = UserDefaults.standard.data(forKey: renderShortcutKey),
           let config = try? JSONDecoder().decode(ShortcutConfig.self, from: data) {
            return config
        }
        return Self.defaultRenderShortcut
    }

    func getRenderInlineShortcut() -> ShortcutConfig {
        if let data = UserDefaults.standard.data(forKey: renderInlineShortcutKey),
           let config = try? JSONDecoder().decode(ShortcutConfig.self, from: data) {
            return config
        }
        return Self.defaultRenderInlineShortcut
    }

    func getRevertShortcut() -> ShortcutConfig {
        if let data = UserDefaults.standard.data(forKey: revertShortcutKey),
           let config = try? JSONDecoder().decode(ShortcutConfig.self, from: data) {
            return config
        }
        return Self.defaultRevertShortcut
    }

    // Set shortcuts
    @MainActor
    func setRenderShortcut(_ config: ShortcutConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: renderShortcutKey)
            reregisterShortcuts()
        }
    }

    @MainActor
    func setRenderInlineShortcut(_ config: ShortcutConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: renderInlineShortcutKey)
            reregisterShortcuts()
        }
    }

    @MainActor
    func setRevertShortcut(_ config: ShortcutConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: revertShortcutKey)
            reregisterShortcuts()
        }
    }

    @MainActor
    private func reregisterShortcuts() {
        unregisterShortcuts()
        registerShortcuts()
    }

    @MainActor
    private func registerShortcuts() {
        let renderHotKeyID = EventHotKeyID(signature: 0x52454E44, id: 1) // 'REND'
        let renderInlineHotKeyID = EventHotKeyID(signature: 0x52454E49, id: 2) // 'RENI'
        let revertHotKeyID = EventHotKeyID(signature: 0x52455645, id: 3) // 'REVE'

        let renderShortcut = getRenderShortcut()
        let renderInlineShortcut = getRenderInlineShortcut()
        let revertShortcut = getRevertShortcut()

        let renderStatus = RegisterEventHotKey(renderShortcut.keyCode, renderShortcut.modifiers, renderHotKeyID, GetApplicationEventTarget(), 0, &renderHotKeyRef)
        let renderInlineStatus = RegisterEventHotKey(renderInlineShortcut.keyCode, renderInlineShortcut.modifiers, renderInlineHotKeyID, GetApplicationEventTarget(), 0, &renderInlineHotKeyRef)
        let revertStatus = RegisterEventHotKey(revertShortcut.keyCode, revertShortcut.modifiers, revertHotKeyID, GetApplicationEventTarget(), 0, &revertHotKeyRef)

        print("Render hotkey registration (\(renderShortcut.displayString)): \(renderStatus)")
        print("Render inline hotkey registration (\(renderInlineShortcut.displayString)): \(renderInlineStatus)")
        print("Revert hotkey registration (\(revertShortcut.displayString)): \(revertStatus)")

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
            print("Hotkey callback triggered!")

            var hotKeyID = EventHotKeyID()
            GetEventParameter(theEvent, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

            print("HotKey ID signature: \(hotKeyID.signature)")

            guard let userData = userData else {
                print("No userData!")
                return noErr
            }

            let manager = Unmanaged<ShortcutManager>.fromOpaque(userData).takeUnretainedValue()

            if hotKeyID.signature == 0x52454E44 {
                print("Render shortcut detected")
                manager.handleRenderShortcut()
            } else if hotKeyID.signature == 0x52454E49 {
                print("Render inline shortcut detected")
                manager.handleRenderInlineShortcut()
            } else if hotKeyID.signature == 0x52455645 {
                print("Revert shortcut detected")
                manager.handleRevertShortcut()
            }

            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventSpec, selfPtr, &eventHandler)
        print("Event handler installation status: \(handlerStatus)")
    }

    @MainActor
    private func unregisterShortcuts() {
        if let ref = renderHotKeyRef {
            UnregisterEventHotKey(ref)
            renderHotKeyRef = nil
        }
        if let ref = renderInlineHotKeyRef {
            UnregisterEventHotKey(ref)
            renderInlineHotKeyRef = nil
        }
        if let ref = revertHotKeyRef {
            UnregisterEventHotKey(ref)
            revertHotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    private func handleRenderShortcut() {
        print("handleRenderShortcut called")
        Task { [weak self] in
            print("Render task started")
            guard let self = self else {
                print("Self is nil in render task")
                return
            }
            print("Calling convertSelectionToSVG")
            await self.clipboardManager.convertSelectionToSVG()
            print("convertSelectionToSVG completed")
        }
    }

    private func handleRenderInlineShortcut() {
        print("handleRenderInlineShortcut called")
        Task { [weak self] in
            print("Render inline task started")
            guard let self = self else {
                print("Self is nil in render inline task")
                return
            }
            print("Calling convertSelectionToSVG with inline mode")
            await self.clipboardManager.convertSelectionToSVG(displayMode: false)
            print("convertSelectionToSVG (inline) completed")
        }
    }

    private func handleRevertShortcut() {
        print("handleRevertShortcut called")
        Task { [weak self] in
            print("Revert task started")
            guard let self = self else {
                print("Self is nil in revert task")
                return
            }
            print("Calling revertSVGToLatex")
            await self.clipboardManager.revertSVGToLatex()
            print("revertSVGToLatex completed")
        }
    }
}
