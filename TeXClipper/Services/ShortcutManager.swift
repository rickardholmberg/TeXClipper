import Foundation
import Carbon
import AppKit

class ShortcutManager {
    private var renderHotKeyRef: EventHotKeyRef?
    private var renderInlineHotKeyRef: EventHotKeyRef?
    private var revertHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private let clipboardManager = ClipboardManager()

    init() {
        registerShortcuts()
    }

    deinit {
        unregisterShortcuts()
    }

    private func registerShortcuts() {
        var renderHotKeyID = EventHotKeyID(signature: 0x52454E44, id: 1) // 'REND'
        var renderInlineHotKeyID = EventHotKeyID(signature: 0x52454E49, id: 2) // 'RENI'
        var revertHotKeyID = EventHotKeyID(signature: 0x52455645, id: 3) // 'REVE'

        let renderModifiers = UInt32(cmdKey | optionKey)
        let renderInlineModifiers = UInt32(cmdKey | optionKey)
        let revertModifiers = UInt32(cmdKey | optionKey | shiftKey)

        let renderKeyCode = UInt32(kVK_ANSI_K)
        let renderInlineKeyCode = UInt32(kVK_ANSI_I)
        let revertKeyCode = UInt32(kVK_ANSI_K)

        let renderStatus = RegisterEventHotKey(renderKeyCode, renderModifiers, renderHotKeyID, GetApplicationEventTarget(), 0, &renderHotKeyRef)
        let renderInlineStatus = RegisterEventHotKey(renderInlineKeyCode, renderInlineModifiers, renderInlineHotKeyID, GetApplicationEventTarget(), 0, &renderInlineHotKeyRef)
        let revertStatus = RegisterEventHotKey(revertKeyCode, revertModifiers, revertHotKeyID, GetApplicationEventTarget(), 0, &revertHotKeyRef)

        print("Render hotkey registration status: \(renderStatus)")
        print("Render inline hotkey registration status: \(renderInlineStatus)")
        print("Revert hotkey registration status: \(revertStatus)")

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

    private func unregisterShortcuts() {
        if let ref = renderHotKeyRef {
            UnregisterEventHotKey(ref)
        }
        if let ref = renderInlineHotKeyRef {
            UnregisterEventHotKey(ref)
        }
        if let ref = revertHotKeyRef {
            UnregisterEventHotKey(ref)
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
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
