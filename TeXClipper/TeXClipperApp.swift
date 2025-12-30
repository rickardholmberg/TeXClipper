import SwiftUI

@MainActor
class AppModel: ObservableObject {
    let shortcutManager = ShortcutManager()
}

@main
struct TeXClipperApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        MenuBarExtra("TeXClipper", systemImage: "function") {
            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        
        Settings {
            ContentView(shortcutManager: appModel.shortcutManager)
        }
    }
}
