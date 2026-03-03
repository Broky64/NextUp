/// `NextUpApp.swift` belongs to the App composition layer in MVVM.
/// It wires the shared `EventManager` view model into the menu bar scene
/// and exposes the settings scene.
import SwiftUI

/// The main entry point for the NextUp menu bar application.
@main
struct NextUpApp: App {
    @StateObject private var eventManager = EventManager.shared
    @AppStorage(SettingsKeys.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(SettingsKeys.menuBarDisplayMode) private var menuBarDisplayMode: MenuBarMode = .currentEvent

    /// Builds the menu bar and settings scenes used by the app.
    ///
    /// - Returns: A scene graph containing the menu bar extra and the settings window scene.
    /// - Note: Updating observed state refreshes menu bar content and can re-render the label text.
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
