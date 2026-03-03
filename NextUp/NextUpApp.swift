import SwiftUI

@main
struct NextUpApp: App {
    @StateObject private var eventManager = EventManager.shared
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("menuBarDisplayMode") private var menuBarDisplayMode: MenuBarMode = .currentEvent
    
    private var shouldRefreshInBackground: Bool {
        showMenuBarIcon || menuBarDisplayMode != .none
    }

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
            .id("\(eventManager.menuBarTitle)|\(menuBarDisplayMode.rawValue)|\(showMenuBarIcon)")
        }
        .menuBarExtraStyle(.window)
        .onAppear {
            eventManager.setRefreshEnabled(shouldRefreshInBackground)
        }
        .onChange(of: showMenuBarIcon) { _, _ in
            eventManager.setRefreshEnabled(shouldRefreshInBackground)
        }
        .onChange(of: menuBarDisplayMode) { _, _ in
            eventManager.setRefreshEnabled(shouldRefreshInBackground)
        }
        
        Settings {
            SettingsView()
        }
    }
}
