import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("showAllDayEvents") private var showAllDayEvents = true
    @AppStorage("showPastEvents") private var showPastEvents = true
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("fontSizeOffset") private var fontSizeOffset: Double = 0.0
    @AppStorage("daysInAdvance") private var daysInAdvance: Int = 3
    @AppStorage("remainingTimeColor") private var remainingTimeColor: String = "Orange"
    @AppStorage("menuBarDisplayMode") private var menuBarDisplayMode: MenuBarMode = .currentEvent
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var textSizeBinding: Binding<Int> {
        Binding(
            get: { Int(fontSizeOffset) + 12 },
            set: { fontSizeOffset = Double($0 - 12) }
        )
    }

    private var activeColor: Color {
        switch remainingTimeColor {
        case "Blue": return .blue
        case "Red": return .red
        case "Green": return .green
        case "Purple": return .purple
        case "Pink": return .pink
        default: return .orange
        }
    }

    var body: some View {
        TabView {
            ScrollView {
                VStack(spacing: 14) {
                    settingsCard("Menu Bar", systemImage: "menubar.rectangle") {
                        Picker("Display", selection: $menuBarDisplayMode) {
                            Text("Icon only").tag(MenuBarMode.none)
                            Text("Current event").tag(MenuBarMode.currentEvent)
                            Text("Upcoming event").tag(MenuBarMode.upcomingEvent)
                        }
                        .pickerStyle(.menu)
                        .onChange(of: menuBarDisplayMode) {
                            EventManager.shared.updateMenuBarTitle()
                            EventManager.shared.refreshFromSettings()
                        }

                        Toggle("Show icon with text", isOn: $showMenuBarIcon)
                            .disabled(menuBarDisplayMode == .none)
                            .onChange(of: showMenuBarIcon) {
                                EventManager.shared.refreshFromSettings()
                            }

                        Text(
                            menuBarDisplayMode == .none
                                ? "Icon is always visible in Icon only mode."
                                : "Turn this off for a cleaner text-only menu bar."
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }

                    settingsCard("Timeline", systemImage: "calendar") {
                        Toggle("Show all-day events", isOn: $showAllDayEvents)
                        Toggle("Show past events", isOn: $showPastEvents)

                        Picker("Look ahead", selection: $daysInAdvance) {
                            Text("1 day").tag(1)
                            Text("2 days").tag(2)
                            Text("3 days").tag(3)
                            Text("7 days").tag(7)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: daysInAdvance) {
                            EventManager.shared.fetchEvents()
                        }
                    }

                    settingsCard("Startup", systemImage: "power") {
                        Toggle("Launch at login", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) {
                                do {
                                    if launchAtLogin {
                                        try SMAppService.mainApp.register()
                                    } else {
                                        try SMAppService.mainApp.unregister()
                                    }
                                } catch {
                                    print("Failed to update Launch at login: \(error.localizedDescription)")
                                    launchAtLogin = SMAppService.mainApp.status == .enabled
                                }
                            }
                            .onAppear {
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                    }
                }
                .padding(16)
            }
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            ScrollView {
                VStack(spacing: 14) {
                    settingsCard("Typography", systemImage: "textformat.size") {
                        HStack {
                            Text("Text size")
                            Spacer()
                            Text("\(textSizeBinding.wrappedValue) pt")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Stepper("Adjust size", value: textSizeBinding, in: 8...24)
                    }

                    settingsCard("Highlights", systemImage: "paintpalette") {
                        Picker("Active time color", selection: $remainingTimeColor) {
                            Text("Orange").tag("Orange")
                            Text("Blue").tag("Blue")
                            Text("Red").tag("Red")
                            Text("Green").tag("Green")
                            Text("Purple").tag("Purple")
                            Text("Pink").tag("Pink")
                        }

                        HStack(spacing: 8) {
                            Circle()
                                .fill(activeColor)
                                .frame(width: 10, height: 10)
                            Text("Preview for ongoing events")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
            }
            .tabItem {
                Label("Appearance", systemImage: "slider.horizontal.3")
            }
        }
        .frame(width: 460, height: 320)
    }

    @ViewBuilder
    private func settingsCard<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
    }
}

#Preview {
    SettingsView()
}
