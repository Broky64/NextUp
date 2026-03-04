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
    @AppStorage(SettingsKeys.daysInAdvance) private var daysInAdvance: Int = 3
    @AppStorage(SettingsKeys.fontSizeOffset) private var popoverFontSizeOffset: Double = 0.0

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var selectedTab: SettingsTab = .general

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
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedVersion = version.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
        let resolvedBuild = build.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"

        if let buildTimestampText = buildTimestampText {
            return "Version \(resolvedVersion) (Build \(resolvedBuild), \(buildTimestampText))"
        }

        return "Version \(resolvedVersion) (Build \(resolvedBuild))"
    }

    private var buildTimestampText: String? {
        guard let executableURL = Bundle.main.executableURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: executableURL.path),
              let buildDate = attributes[.modificationDate] as? Date else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return "built \(formatter.string(from: buildDate))"
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

                Section {
                    Picker("Look Ahead", selection: $daysInAdvance) {
                        Text("1 day").tag(1)
                        Text("2 days").tag(2)
                        Text("3 days").tag(3)
                        Text("7 days").tag(7)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: daysInAdvance) { _ in
                        eventManager.fetchEvents()
                    }
                } header: {
                    Text("Events")
                } footer: {
                    Text("Choose how many days of upcoming events are shown in NextUp.")
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
                HStack {
                    Text("Popover Text Size")
                    Spacer()
                    Text("\(popoverFontSizeOffset >= 0 ? "+" : "")\(Int(popoverFontSizeOffset))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Slider(
                        value: $popoverFontSizeOffset,
                        in: -2...8,
                        step: 1
                    )
                    .frame(width: 150)
                }
            } header: {
                Text("Popover")
            } footer: {
                Text("Changes the text size used in the event popover.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                popoverPreview
            } header: {
                Text("Live Preview")
            }
        }
        .formStyle(.grouped)
    }

    private var popoverPreview: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TODAY")
                .font(.system(size: 9 + popoverFontSizeOffset, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 2)

            previewRow(timeText: "23 min", timeSuffix: " left", title: "Team standup")
            previewRow(timeText: "11:30", timeSuffix: nil, title: "Product sync with design")
        }
        .padding(.vertical, 4)
        .frame(width: 300, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func previewRow(timeText: String, timeSuffix: String?, title: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor)
                .frame(width: 3)
                .padding(.vertical, 4)

            if let timeSuffix {
                (Text(timeText)
                    .font(.system(size: 12 + popoverFontSizeOffset, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary) +
                 Text(timeSuffix)
                    .font(.system(size: 11 + popoverFontSizeOffset, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange))
                .frame(width: 82, alignment: .leading)
            } else {
                Text(timeText)
                    .font(.system(size: 12 + popoverFontSizeOffset, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 82, alignment: .leading)
            }

            Text("·")
                .foregroundColor(.secondary.opacity(0.5))
                .font(.system(size: 12 + popoverFontSizeOffset, weight: .bold))

            Text(title)
                .font(.system(size: 12 + popoverFontSizeOffset, weight: .medium, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 22)
        .padding(.leading, 8)
        .padding(.trailing, 2)
        .padding(.vertical, 2)
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
            Image("AboutAppIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
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
