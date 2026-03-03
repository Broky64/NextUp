/// `SettingsView.swift` belongs to the View layer in MVVM.
/// It provides configuration screens that read and mutate `EventManager`
/// and persisted user preferences.
import SwiftUI
import ServiceManagement
import EventKit
import AppKit

private enum SettingsTab: Hashable {
    case general
    case appearance
    case calendars
    case about
}

/// Multi-tab settings interface for system, appearance, calendar, and project metadata.
struct SettingsView: View {
    @ObservedObject private var eventManager = EventManager.shared
    @AppStorage(SettingsKeys.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(SettingsKeys.menuBarDisplayMode) private var menuBarDisplayMode: MenuBarMode = .currentEvent
    @AppStorage(SettingsKeys.menuBarCharacterLimit) private var characterLimit: Int = 20

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var selectedTab: SettingsTab = .general

    private var previewTitle: String {
        let sample = "Quarterly roadmap review with product and engineering stakeholders"
        return eventManager.truncateTitle(sample, limit: characterLimit)
    }

    private var groupedCalendars: [(source: String, calendars: [EKCalendar])] {
        let grouped = Dictionary(grouping: eventManager.availableCalendars) { calendar in
            let source = calendar.source.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return source.isEmpty ? "Other" : source
        }

        return grouped.keys.sorted().map { source in
            let calendars = (grouped[source] ?? []).sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return (source, calendars)
        }
    }

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (Build \(build))"
    }

    /// Builds the full tabbed settings window content.
    ///
    /// - Returns: A tab-based SwiftUI interface used by the app settings scene.
    /// - Note: Changing certain controls updates `UserDefaults`, can refetch events, and may register login items.
    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
                .tag(SettingsTab.appearance)

            calendarsTab
                .tabItem { Label("Calendars", systemImage: "calendar") }
                .tag(SettingsTab.calendars)

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 480, height: 450)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if eventManager.accessGranted {
                eventManager.fetchEvents()
            }
        }
        .onChange(of: selectedTab) { newValue in
            if newValue == .calendars && eventManager.accessGranted {
                eventManager.fetchEvents()
            }
        }
    }

    // MARK: - General Tab
    private var generalTab: some View {
        VStack {
            Form {
                Section {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _ in updateLaunchAtLogin() }
                } header: {
                    Text("System")
                }

                Section {
                    Picker("Display Mode", selection: $menuBarDisplayMode) {
                        Text("None").tag(MenuBarMode.none)
                        Text("Current Event").tag(MenuBarMode.currentEvent)
                        Text("Upcoming Event").tag(MenuBarMode.upcomingEvent)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: menuBarDisplayMode) { _ in
                        eventManager.updateMenuBarTitle()
                        eventManager.refreshFromSettings()
                    }

                    Toggle("Show Icon with Text", isOn: $showMenuBarIcon)
                        .disabled(menuBarDisplayMode == .none)
                        .onChange(of: showMenuBarIcon) { _ in
                            eventManager.refreshFromSettings()
                        }
                } header: {
                    Text("Menu Bar")
                } footer: {
                    Text("NextUp refreshes every minute to keep your schedule accurate without draining battery.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            
            Spacer()
            
            Button("Quit NextUp") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("q", modifiers: .command)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Appearance Tab
    private var appearanceTab: some View {
        Form {
            Section {
                HStack {
                    Text("Character Limit")
                    Spacer()
                    Text("\(characterLimit)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    
                    Slider(
                        value: Binding(
                            get: { Double(characterLimit) },
                            set: { characterLimit = Int($0.rounded()) }
                        ),
                        in: 5...50,
                        step: 1
                    )
                    .frame(width: 150)
                    .onChange(of: characterLimit) { _ in
                        eventManager.updateMenuBarTitle()
                    }
                }
            } header: {
                Text("Menu Bar Text Truncation")
            }

            Section {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.secondary)
                    Text(previewTitle.isEmpty ? " " : previewTitle)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            } header: {
                Text("Live Preview")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Calendars Tab
    private var calendarsTab: some View {
        Form {
            if !eventManager.accessGranted {
                UnavailableStateRow(
                    title: "Access Required",
                    systemImage: "lock.shield",
                    message: "Please enable Calendar access in System Settings."
                )
            } else if groupedCalendars.isEmpty {
                UnavailableStateRow(
                    title: "No Calendars",
                    systemImage: "calendar.badge.exclamationmark",
                    message: nil
                )
            } else {
                ForEach(groupedCalendars, id: \.source) { group in
                    Section {
                        ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(nsColor: calendar.color))
                                    .frame(width: 10, height: 10)

                                Text(calendar.title)
                                    .foregroundStyle(.primary)

                                Spacer()

                                Toggle("", isOn: Binding(
                                    get: { eventManager.isCalendarEnabled(id: calendar.calendarIdentifier) },
                                    set: { isEnabled in
                                        if isEnabled != eventManager.isCalendarEnabled(id: calendar.calendarIdentifier) {
                                            eventManager.toggleCalendar(id: calendar.calendarIdentifier)
                                        }
                                    }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .tint(Color(nsColor: .controlAccentColor))
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text(group.source)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About Tab
    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 8)

            VStack(spacing: 4) {
                Text("NextUp")
                    .font(.system(size: 24, weight: .bold))
                
                Text(appVersionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let repositoryURL = URL(string: "https://github.com/Broky64/NextUp") {
                Link(destination: repositoryURL) {
                    Label("View on GitHub", systemImage: "link")
                }
                .buttonStyle(.link)
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor)) 
    }

    // MARK: - Logic
    private func updateLaunchAtLogin() {
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
}

private struct UnavailableStateRow: View {
    let title: String
    let systemImage: String
    let message: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            if let message, !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
    }
}

#Preview {
    SettingsView()
}
