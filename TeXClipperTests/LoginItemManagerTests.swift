import XCTest
import ServiceManagement
@testable import TeXClipper

final class LoginItemManagerTests: XCTestCase {

    var loginItemManager: LoginItemManager!

    // Class-level teardown that runs AFTER all tests in this class complete
    // This is a final safety net to ensure login item is disabled even if individual
    // test tearDown methods fail or are interrupted
    override class func tearDown() {
        super.tearDown()

        // Final cleanup attempt
        let manager = LoginItemManager.shared
        try? manager.setEnabled(false)

        // Verify cleanup succeeded
        if manager.isEnabled {
            print("ERROR: Login item still enabled after test suite completion!")
            print("Please manually disable via System Settings > General > Login Items")
        }
    }

    override func setUp() async throws {
        loginItemManager = LoginItemManager.shared

        // Ensure we start from a known state - unconditionally attempt to disable
        // Use try? since the item might already be disabled, which could throw
        try? loginItemManager.setEnabled(false)
    }

    override func tearDown() async throws {
        // Clean up - ALWAYS attempt to disable login item, even if tests failed
        // This ensures we don't leave login items enabled after test runs
        // Use try? since it's already disabled in most cases and we don't want
        // tearDown itself to throw and mask test failures
        try? loginItemManager.setEnabled(false)

        // Additional safety check: verify it's actually disabled
        // If this fails, print a warning so developers know to manually clean up
        if loginItemManager.isEnabled {
            print("WARNING: Failed to disable login item in tearDown. Manual cleanup may be required.")
        }
    }

    // MARK: - Basic Functionality Tests

    func testLoginItemManagerIsSingleton() {
        let instance1 = LoginItemManager.shared
        let instance2 = LoginItemManager.shared

        XCTAssertTrue(instance1 === instance2, "LoginItemManager should be a singleton")
    }

    func testInitialStateIsDisabled() {
        // After setUp, login item should be disabled
        XCTAssertFalse(loginItemManager.isEnabled, "Login item should initially be disabled")
    }

    func testEnableLoginItem() throws {
        // Enable the login item
        try loginItemManager.setEnabled(true)

        // Verify it's enabled
        XCTAssertTrue(loginItemManager.isEnabled, "Login item should be enabled after calling setEnabled(true)")

        // Verify the system status directly
        let systemStatus = SMAppService.mainApp.status
        XCTAssertEqual(systemStatus, .enabled, "SMAppService should report status as enabled")
    }

    func testDisableLoginItem() throws {
        // First enable it
        try loginItemManager.setEnabled(true)
        XCTAssertTrue(loginItemManager.isEnabled, "Login item should be enabled")

        // Then disable it
        try loginItemManager.setEnabled(false)

        // Verify it's disabled
        XCTAssertFalse(loginItemManager.isEnabled, "Login item should be disabled after calling setEnabled(false)")

        // Verify the system status directly
        let systemStatus = SMAppService.mainApp.status
        XCTAssertEqual(systemStatus, .notRegistered, "SMAppService should report status as notRegistered")
    }

    func testToggleLoginItem() throws {
        // Start disabled
        XCTAssertFalse(loginItemManager.isEnabled, "Should start disabled")

        // Enable
        try loginItemManager.setEnabled(true)
        XCTAssertTrue(loginItemManager.isEnabled, "Should be enabled after first toggle")

        // Disable
        try loginItemManager.setEnabled(false)
        XCTAssertFalse(loginItemManager.isEnabled, "Should be disabled after second toggle")

        // Enable again
        try loginItemManager.setEnabled(true)
        XCTAssertTrue(loginItemManager.isEnabled, "Should be enabled after third toggle")
    }

    // MARK: - Idempotency Tests

    func testEnableWhenAlreadyEnabled() throws {
        // Enable the login item
        try loginItemManager.setEnabled(true)
        XCTAssertTrue(loginItemManager.isEnabled, "Login item should be enabled")

        // Enable again (should be idempotent)
        XCTAssertNoThrow(try loginItemManager.setEnabled(true), "Enabling when already enabled should not throw")

        // Should still be enabled
        XCTAssertTrue(loginItemManager.isEnabled, "Login item should still be enabled")
    }

    func testDisableWhenAlreadyDisabled() throws {
        // Ensure it's disabled
        XCTAssertFalse(loginItemManager.isEnabled, "Login item should be disabled")

        // Disable again (should be idempotent)
        XCTAssertNoThrow(try loginItemManager.setEnabled(false), "Disabling when already disabled should not throw")

        // Should still be disabled
        XCTAssertFalse(loginItemManager.isEnabled, "Login item should still be disabled")
    }

    // MARK: - State Consistency Tests

    func testIsEnabledReflectsSystemState() throws {
        // Test that isEnabled accurately reflects SMAppService.mainApp.status

        // Disabled state
        try loginItemManager.setEnabled(false)
        XCTAssertEqual(loginItemManager.isEnabled, SMAppService.mainApp.status == .enabled,
                      "isEnabled should match SMAppService status (disabled)")

        // Enabled state
        try loginItemManager.setEnabled(true)
        XCTAssertEqual(loginItemManager.isEnabled, SMAppService.mainApp.status == .enabled,
                      "isEnabled should match SMAppService status (enabled)")
    }

    func testMultipleReadsOfIsEnabled() throws {
        // Enable the login item
        try loginItemManager.setEnabled(true)

        // Read isEnabled multiple times
        let firstRead = loginItemManager.isEnabled
        let secondRead = loginItemManager.isEnabled
        let thirdRead = loginItemManager.isEnabled

        // All reads should be consistent
        XCTAssertTrue(firstRead, "First read should return true")
        XCTAssertTrue(secondRead, "Second read should return true")
        XCTAssertTrue(thirdRead, "Third read should return true")
        XCTAssertEqual(firstRead, secondRead, "Consecutive reads should be equal")
        XCTAssertEqual(secondRead, thirdRead, "Consecutive reads should be equal")
    }

    // MARK: - Cleanup Tests

    func testCleanupHappensEvenAfterEnabling() throws {
        // Enable the login item
        try loginItemManager.setEnabled(true)
        XCTAssertTrue(loginItemManager.isEnabled, "Should be enabled")

        // Don't disable it here - let tearDown handle it
        // This simulates a test that enables the login item and then ends
        // tearDown should clean this up automatically
    }

    func testCleanupIsIdempotent() throws {
        // Ensure it's already disabled
        try loginItemManager.setEnabled(false)
        XCTAssertFalse(loginItemManager.isEnabled, "Should be disabled")

        // Call setEnabled(false) again in tearDown shouldn't cause issues
        // This tests that calling setEnabled(false) when already disabled is safe
    }

    // MARK: - Integration Tests

    func testLoginItemPersistsAcrossReads() throws {
        // Enable login item
        try loginItemManager.setEnabled(true)

        // Simulate reading from a different instance (in practice, this is the same singleton)
        let anotherReference = LoginItemManager.shared

        // Should still be enabled
        XCTAssertTrue(anotherReference.isEnabled, "Login item state should persist across references")

        // Disable it
        try anotherReference.setEnabled(false)

        // Original reference should see the change
        XCTAssertFalse(loginItemManager.isEnabled, "State change should be visible across references")
    }

    func testStatusMatchesExpectedValues() throws {
        // Test disabled state
        try loginItemManager.setEnabled(false)
        let disabledStatus = SMAppService.mainApp.status
        XCTAssertTrue(disabledStatus == .notRegistered || disabledStatus == .notFound,
                     "Disabled status should be notRegistered or notFound, got: \(disabledStatus)")

        // Test enabled state
        try loginItemManager.setEnabled(true)
        let enabledStatus = SMAppService.mainApp.status
        XCTAssertEqual(enabledStatus, .enabled, "Enabled status should be .enabled, got: \(enabledStatus)")
    }
}
