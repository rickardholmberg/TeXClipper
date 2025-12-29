import Foundation
import ServiceManagement

class LoginItemManager {
    static let shared = LoginItemManager()

    private init() {}

    var isEnabled: Bool {
        get {
            // Check if the app is registered as a login item
            SMAppService.mainApp.status == .enabled
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            // Register as login item
            if SMAppService.mainApp.status == .enabled {
                print("Login item already enabled")
                return
            }

            try SMAppService.mainApp.register()
            print("Successfully registered as login item")
        } else {
            // Unregister as login item
            if SMAppService.mainApp.status == .notRegistered {
                print("Login item already disabled")
                return
            }

            try SMAppService.mainApp.unregister()
            print("Successfully unregistered as login item")
        }
    }
}
