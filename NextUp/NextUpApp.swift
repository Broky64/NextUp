import SwiftUI

@main
struct NextUpApp: App {
    @StateObject private var eventManager = EventManager.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView(eventManager: eventManager)
        } label: {
            Text(Image(systemName: "calendar.badge.clock")) + Text(eventManager.menuBarTitle.isEmpty ? "" : " \(eventManager.menuBarTitle)")
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
        }
    }
}
