/// `ContentView.swift` belongs to the View layer in MVVM.
/// It renders the menu bar popover UI from `EventManager` state and
/// routes user interactions back to the view model.
import SwiftUI
import EventKit
import AppKit

/// Represents events grouped by day for sectioned popover rendering.
struct EventGroup: Identifiable {
    /// The calendar day used as the group identity.
    let day: Date
    /// Localized uppercase header displayed for the day section.
    let title: String
    /// Events that belong to the section day.
    let events: [EKEvent]
    /// Stable identifier used by SwiftUI list diffing.
    var id: Date { day }
}

/// Main popover view displayed from the menu bar extra.
struct ContentView: View {
    /// Shared event view model injected from the app entry point.
    @ObservedObject var eventManager: EventManager
    
    @AppStorage(SettingsKeys.showAllDayEvents) private var showAllDayEvents = true
    @AppStorage(SettingsKeys.showPastEvents) private var showPastEvents = true
    @AppStorage(SettingsKeys.fontSizeOffset) private var fontSizeOffset: Double = 0.0

    private static let sectionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E MMM d"
        return formatter
    }()
    
    /// Groups filtered events into day-based sections for display.
    var groupedEvents: [EventGroup] {
        let now = eventManager.currentMinute
        let calendar = Calendar.current
        var groupedByDay: [Date: [EKEvent]] = [:]
        
        for event in eventManager.upcomingEvents {
            if !showAllDayEvents && event.isAllDay { continue }
            if !showPastEvents && !event.isAllDay && event.endDate <= now { continue }
            
            let effectiveDate: Date
            if event.startDate < now, event.endDate > now {
                // Keep spanning events visible in today's group while active.
                effectiveDate = now
            } else {
                effectiveDate = event.startDate
            }
            
            let day = calendar.startOfDay(for: effectiveDate)
            groupedByDay[day, default: []].append(event)
        }
        
        return groupedByDay.keys.sorted().map { day in
            let title: String
            if calendar.isDateInToday(day) {
                title = "TODAY"
            } else if calendar.isDateInTomorrow(day) {
                title = "TOMORROW"
            } else {
                title = Self.sectionFormatter.string(from: day).uppercased()
            }
            
            let events = (groupedByDay[day] ?? []).sorted { $0.startDate < $1.startDate }
            return EventGroup(day: day, title: title, events: events)
        }
    }

    /// Builds the popover interface for permissions, events, and quick actions.
    ///
    /// - Returns: A SwiftUI view tree sized for menu bar popover presentation.
    /// - Note: Renders from published `EventManager` state and updates automatically on minute ticks.
    var body: some View {
        VStack(spacing: 0) {
            if !eventManager.accessGranted {
                AccessDeniedView(fontSizeOffset: fontSizeOffset) {
                    eventManager.openSystemSettings()
                }
            } else if groupedEvents.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 24))
                        .foregroundColor(.primary.opacity(0.5))
                    Text("No upcoming events")
                        .font(.system(size: 12 + fontSizeOffset, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 32)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(groupedEvents) { group in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title)
                                    .font(.system(size: 9 + fontSizeOffset, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 2)
                                
                                ForEach(group.events, id: \.calendarItemIdentifier) { event in
                                    EventRowView(
                                        event: event,
                                        fontSizeOffset: fontSizeOffset,
                                        currentMinute: eventManager.currentMinute,
                                        openEvent: { selectedEvent in
                                            eventManager.openEventInCalendar(event: selectedEvent)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 400)
            }
            
            VStack(spacing: 0) {
                Divider()
                    .padding(.bottom, 2)
                
                settingsButton
                
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack {
                        Text("Quit NextUp")
                        Spacer()
                        Text("⌘Q").foregroundColor(.secondary).font(.system(size: 11))
                    }
                    .font(.system(size: 12 + fontSizeOffset))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.bottom, 2)
        }
        .frame(width: 300)
        .onAppear { eventManager.handleMinuteTick() }
    }

    @ViewBuilder
    private var settingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                settingsButtonLabel
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
        } else {
            Button {
                openLegacySettingsWindow()
            } label: {
                settingsButtonLabel
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    private var settingsButtonLabel: some View {
        HStack {
            Text("Settings")
            Spacer()
            Text("⌘,").foregroundColor(.secondary).font(.system(size: 11))
        }
        .font(.system(size: 12 + fontSizeOffset) )
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private func openLegacySettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowController.shared.show()
    }
}

@MainActor
private final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let rootView = SettingsView()
            let hostingController = NSHostingController(rootView: rootView)

            let settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow.title = "Settings"
            settingsWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            settingsWindow.setContentSize(NSSize(width: 480, height: 450))
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.center()
            settingsWindow.setFrameAutosaveName("NextUpSettingsWindow")

            window = settingsWindow
        }

        window?.makeKeyAndOrderFront(nil)
    }
}

struct AccessDeniedView: View {
    /// Additional text scaling used to match global appearance preferences.
    let fontSizeOffset: Double
    /// Callback that opens Calendar privacy settings when permission is missing.
    let openSystemSettings: () -> Void
    
    /// Builds the permission-required state shown when calendar access is denied.
    ///
    /// - Returns: A centered call-to-action view guiding users to System Settings.
    /// - Note: Triggering the action opens macOS settings outside the app.
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.lock.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.secondary)
            
            Text("Calendar Access Required")
                .font(.system(size: 13 + fontSizeOffset, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
            
            Text("NextUp needs permission to show your events. Please enable Calendar access in System Settings > Privacy & Security.")
                .font(.system(size: 11 + fontSizeOffset, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            
            Button("Open System Settings", action: openSystemSettings)
                .font(.system(size: 12 + fontSizeOffset, weight: .semibold, design: .rounded))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

struct EventRowView: View {
    /// Event represented by the current row.
    let event: EKEvent
    /// Additional text scaling used to match user appearance preferences.
    let fontSizeOffset: Double
    /// Minute-aligned current timestamp used for active/past state calculations.
    let currentMinute: Date
    /// Callback invoked when the row is selected.
    let openEvent: (EKEvent) -> Void
    
    @AppStorage(SettingsKeys.remainingTimeColor) private var remainingTimeColor: String = "Orange"
    @State private var isHovering = false

    private var displayTitle: String {
        let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled event" : title
    }
    
    /// Accent color used for active-event remaining time text.
    var activeColor: Color {
        switch remainingTimeColor {
        case "Blue": return .blue
        case "Red": return .red
        case "Green": return .green
        case "Purple": return .purple
        case "Pink": return .pink
        default: return .orange
        }
    }
    
    private func roundedMinutes(from startDate: Date, to endDate: Date) -> Int {
        let calendar = Calendar.current
        let seconds = calendar.dateComponents([.second], from: startDate, to: endDate).second ?? 0
        return max(0, Int((Double(seconds) / 60.0).rounded()))
    }
    
    /// Builds a single interactive event row with timing and title metadata.
    ///
    /// - Returns: A hoverable button row that opens the selected event in Calendar.
    /// - Note: Invokes `openEvent` on tap, which can close the popover and launch Calendar.
    var body: some View {
        let now = currentMinute
        let isPast = !event.isAllDay && event.endDate < now
        let isActive = !event.isAllDay && event.startDate <= now && event.endDate > now
        
        Button {
            openEvent(event)
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(nsColor: event.calendar.color))
                    .frame(width: 3)
                    .padding(.vertical, 4)
                    
                if event.isAllDay {
                    Text("All Day")
                        .font(.system(size: 12 + fontSizeOffset, weight: .medium, design: .monospaced))
                        .foregroundColor(isPast ? .secondary.opacity(0.6) : .secondary)
                        .frame(width: 90, alignment: .leading)
                } else if isActive {
                    let diff = roundedMinutes(from: now, to: event.endDate)
                    let h = diff / 60
                    let m = diff % 60
                    let timeValue = h > 0 ? "\(h)h \(m)m" : "\(m) min"
                    
                    (Text(timeValue)
                        .font(.system(size: 12 + fontSizeOffset, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary) +
                     Text(" left")
                        .font(.system(size: 11 + fontSizeOffset, weight: .bold, design: .monospaced))
                        .foregroundColor(activeColor))
                        .frame(width: 90, alignment: .leading)
                } else {
                    Text(event.startDate, style: .time)
                        .font(.system(size: 12 + fontSizeOffset, weight: .medium, design: .monospaced))
                        .foregroundColor(isPast ? .secondary.opacity(0.6) : .secondary)
                        .frame(width: 90, alignment: .leading)
                }
                
                Text("·")
                    .foregroundColor(.secondary.opacity(0.5))
                    .font(.system(size: 12 + fontSizeOffset, weight: .bold))
                    
                Text(displayTitle)
                    .font(.system(size: 12 + fontSizeOffset, weight: .medium, design: .rounded))
                    .foregroundColor(isPast ? .secondary.opacity(0.6) : .primary)
                    .lineLimit(1)
                    
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(height: 22)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(isHovering ? Color.primary.opacity(0.08) : Color.clear)
        .cornerRadius(4)
        .padding(.horizontal, 8)
        .onHover { hovering in
            isHovering = hovering
        }
        .help("Click to open in Calendar")
    }
}
