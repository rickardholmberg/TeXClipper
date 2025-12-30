import Foundation
import ServiceManagement

protocol LoginItemServicing {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

struct SystemLoginItemService: LoginItemServicing {
    private let appService: SMAppService

    init(appService: SMAppService = .mainApp) {
        self.appService = appService
    }

    var status: SMAppService.Status {
        appService.status
    }

    func register() throws {
        try appService.register()
    }

    func unregister() throws {
        try appService.unregister()
    }
}

class LoginItemManager {
    static var shared = LoginItemManager()

    private let service: LoginItemServicing

    init(service: LoginItemServicing = SystemLoginItemService()) {
        self.service = service
    }

    var isEnabled: Bool {
        service.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            // Register as login item
            if service.status == .enabled {
                print("Login item already enabled")
                return
            }

            try service.register()
            print("Successfully registered as login item")
        } else {
            // Unregister as login item
            if service.status == .notRegistered {
                print("Login item already disabled")
                return
            }

            try service.unregister()
            print("Successfully unregistered as login item")
        }
    }
}
