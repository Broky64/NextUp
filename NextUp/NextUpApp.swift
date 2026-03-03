import SwiftUI

@main
struct NextUpApp: App {
    @StateObject private var eventManager = EventManager.shared
    @AppStorage(SettingsKeys.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(SettingsKeys.menuBarDisplayMode) private var menuBarDisplayMode: MenuBarMode = .currentEvent

    var body: some Scene {
        MenuBarExtra {
            ContentView(eventManager: eventManager)
        } label: {
            let hasTitle = !eventManager.menuBarTitle.isEmpty
            let shouldShowIcon = menuBarDisplayMode == .none || !hasTitle || showMenuBarIcon

            Group {
                if hasTitle {
                    HStack(spacing: 4) {
                        if shouldShowIcon {
                            Image(systemName: "calendar.badge.clock")
                        }
                        Text(eventManager.menuBarTitle)
                            .lineLimit(1)
                    }
                    .monospacedDigit()
                } else if shouldShowIcon {
                    Image(systemName: "calendar.badge.clock")
                } else {
                    Text(" ")
                }
            }
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
        }
    }
}
