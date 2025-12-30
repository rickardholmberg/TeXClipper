import XCTest
import Carbon
@testable import TeXClipper

final class ShortcutManagerTests: XCTestCase {

    func testShortcutConfigCodable() throws {
        let config = ShortcutConfig(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey | shiftKey))
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        
        let decoder = JSONDecoder()
        let decodedConfig = try decoder.decode(ShortcutConfig.self, from: data)
        
        XCTAssertEqual(decodedConfig.keyCode, config.keyCode)
        XCTAssertEqual(decodedConfig.modifiers, config.modifiers)
    }
    
    func testModifierString() {
        // Test single modifiers
        let cmdConfig = ShortcutConfig(keyCode: 0, modifiers: UInt32(cmdKey))
        XCTAssertEqual(cmdConfig.modifierString, "⌘")
        
        let optConfig = ShortcutConfig(keyCode: 0, modifiers: UInt32(optionKey))
        XCTAssertEqual(optConfig.modifierString, "⌥")
        
        let ctrlConfig = ShortcutConfig(keyCode: 0, modifiers: UInt32(controlKey))
        XCTAssertEqual(ctrlConfig.modifierString, "⌃")
        
        let shiftConfig = ShortcutConfig(keyCode: 0, modifiers: UInt32(shiftKey))
        XCTAssertEqual(shiftConfig.modifierString, "⇧")
        
        // Test combinations (order matters in implementation: cmd, opt, ctrl, shift)
        let allConfig = ShortcutConfig(keyCode: 0, modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey))
        XCTAssertEqual(allConfig.modifierString, "⌘⌥⌃⇧")
        
        let cmdShiftConfig = ShortcutConfig(keyCode: 0, modifiers: UInt32(cmdKey | shiftKey))
        XCTAssertEqual(cmdShiftConfig.modifierString, "⌘⇧")
    }
    
    func testFallbackKeyString() {
        // Test some known key codes from the fallback switch statement
        
        // A
        let aConfig = ShortcutConfig(keyCode: UInt32(kVK_ANSI_A), modifiers: 0)
        XCTAssertEqual(aConfig.fallbackKeyString, "A")
        
        // Numbers
        let oneConfig = ShortcutConfig(keyCode: UInt32(kVK_ANSI_1), modifiers: 0)
        XCTAssertEqual(oneConfig.fallbackKeyString, "1")
        
        // Special keys
        let spaceConfig = ShortcutConfig(keyCode: UInt32(kVK_Space), modifiers: 0)
        XCTAssertEqual(spaceConfig.fallbackKeyString, "␣")
        
        let returnConfig = ShortcutConfig(keyCode: UInt32(kVK_Return), modifiers: 0)
        XCTAssertEqual(returnConfig.fallbackKeyString, "↩")
        
        // Arrows
        let leftConfig = ShortcutConfig(keyCode: UInt32(kVK_LeftArrow), modifiers: 0)
        XCTAssertEqual(leftConfig.fallbackKeyString, "←")
    }
    
    // Note: We cannot easily test keyString because it depends on the system's current keyboard layout
    // via KeyboardLayoutManager, which uses Carbon APIs that are hard to mock in this context.
    // However, we know it falls back to fallbackKeyString if the system API fails or returns nil.
}
