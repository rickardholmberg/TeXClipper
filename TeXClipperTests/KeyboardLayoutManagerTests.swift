import XCTest
import Carbon
@testable import TeXClipper

final class KeyboardLayoutManagerTests: XCTestCase {
    
    func testCharacterForKeyCode() {
        // Test 'A' key (ANSI_A = 0x00)
        // In most layouts, this produces a character.
        let char = KeyboardLayoutManager.shared.character(for: UInt32(kVK_ANSI_A))
        XCTAssertNotNil(char, "Should return a character for 'A' key")
        
        if let char = char {
            XCTAssertFalse(char.isEmpty, "Character should not be empty")
        }
    }
    
    func testCacheBehavior() {
        // Call multiple times to ensure cache doesn't crash or return inconsistent results
        let char1 = KeyboardLayoutManager.shared.character(for: UInt32(kVK_ANSI_B))
        let char2 = KeyboardLayoutManager.shared.character(for: UInt32(kVK_ANSI_B))
        
        XCTAssertEqual(char1, char2, "Should return consistent results")
    }
}
