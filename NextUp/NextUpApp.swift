import SwiftUI

@main
struct NextUpApp: App {
    @StateObject private var eventManager = EventManager.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView(eventManager: eventManager)
        } label: {
            Group {
                if eventManager.menuBarTitle.isEmpty {
                    Image(systemName: "calendar.badge.clock")
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.clock")
                        Text(eventManager.menuBarTitle)
                            .lineLimit(1)
                    }
                    .monospacedDigit()
                }
            }
            .id(eventManager.menuBarTitle)
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
        }
    }
}
