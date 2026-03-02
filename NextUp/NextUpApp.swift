import SwiftUI

@main
struct NextUpApp: App {
    @StateObject private var eventManager = EventManager.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(eventManager)
        } label: {
            Label(eventManager.menuBarTitle, systemImage: "calendar.badge.clock")
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
        }
    }
}
