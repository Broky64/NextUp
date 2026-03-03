/// `EventManager.swift` is the ViewModel layer in MVVM.
/// It owns calendar permissions, event fetching, filtering, and state
/// published to SwiftUI views.
import Foundation
import EventKit
import Combine
import AppKit
import SwiftUI

/// Controls which event context is shown in the menu bar title.
enum MenuBarMode: String, CaseIterable {
    /// Hides all title text and only shows the icon when configured.
    case none
    /// Prioritizes the currently running event and falls back to the next event.
    case currentEvent
    /// Prioritizes the next event and falls back to the currently running event.
    case upcomingEvent
}

/// Defines `UserDefaults` keys used by NextUp settings.
enum SettingsKeys {
    /// Persists whether the menu bar icon is visible when text is also shown.
    static let showMenuBarIcon = "showMenuBarIcon"
    /// Persists the selected menu bar display mode.
    static let menuBarDisplayMode = "menuBarDisplayMode"
    /// Persists the title truncation limit for menu bar text.
    static let menuBarCharacterLimit = "menuBarCharacterLimit"
    /// Persists how many days ahead the app should query events.
    static let daysInAdvance = "daysInAdvance"
    /// Persists calendar identifiers excluded from event results.
    static let disabledCalendarIDs = "disabledCalendarIDs"
    /// Persists whether all-day events are visible in the menu content.
    static let showAllDayEvents = "showAllDayEvents"
    /// Persists whether past events are visible in the menu content.
    static let showPastEvents = "showPastEvents"
    /// Persists the user-selected text scaling offset.
    static let fontSizeOffset = "fontSizeOffset"
    /// Persists the color preset for active event remaining-time text.
    static let remainingTimeColor = "remainingTimeColor"
}

/// Central view model that synchronizes EventKit data with menu bar UI state.
final class EventManager: ObservableObject {
    /// Shared singleton used by the app and settings scenes.
    static let shared = EventManager()
    
    private let store = EKEventStore()
    
    /// Ordered list of fetched events shown in the popover UI.
    @Published var upcomingEvents: [EKEvent] = []
    /// Full list of calendars available from EventKit, regardless of filtering.
    @Published var availableCalendars: [EKCalendar] = []
    /// Indicates whether calendar read access is currently granted.
    @Published var accessGranted = false
    /// Current text rendered in the menu bar label.
    @Published var menuBarTitle: String = ""
    /// Current minute-aligned timestamp used to drive countdown calculations.
    @Published var currentMinute: Date = Date()
    
    private var calendar: Calendar { Calendar.current }
    private var timerCancellable: AnyCancellable?
    private var alignmentCancellable: AnyCancellable?
    private var refreshEnabled = true
    private var lastProcessedMinute: Date?
    private var lastKnownDayStart = Calendar.current.startOfDay(for: Date())
    private var lastEventsFetchAt: Date?
    private let periodicRefreshInterval: TimeInterval = 15 * 60
    private var cachedSortedCalendars: [EKCalendar] = []
    private var isCalendarCacheValid = false
    private var notificationObservers: [NSObjectProtocol] = []
    private var workspaceNotificationObservers: [NSObjectProtocol] = []
    
    private init() {
        migrateLegacyDisabledCalendarIDsIfNeeded()
        refreshEnabled = shouldRefreshInBackground()
        setupSystemObservers()
        requestAccess()
    }
    
    deinit {
        stopTimer()
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceNotificationObservers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
    }

    private var disabledCalendarIDSet: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: SettingsKeys.disabledCalendarIDs) ?? [])
    }

    /// Calendars included in event queries after applying disabled-calendar settings.
    var enabledCalendars: [EKCalendar] {
        let disabled = disabledCalendarIDSet
        return availableCalendars.filter { !disabled.contains($0.calendarIdentifier) }
    }
    
    /// Enables or disables background refresh scheduling.
    ///
    /// - Parameters:
    ///   - enabled: `true` to keep minute-based refresh active, `false` to stop it.
    /// - Returns: `Void`.
    /// - Note: Stopping refresh pauses timer-driven menu bar updates until re-enabled.
    func setRefreshEnabled(_ enabled: Bool) {
        refreshEnabled = enabled
        refreshTimerIfNeeded()
    }
    
    /// Recomputes refresh behavior from persisted menu bar settings.
    ///
    /// - Parameters: None.
    /// - Returns: `Void`.
    /// - Note: This may start or stop active timers, which changes update frequency and battery usage.
    func refreshFromSettings() {
        setRefreshEnabled(shouldRefreshInBackground())
    }
    
    private func shouldRefreshInBackground() -> Bool {
        let defaults = UserDefaults.standard
        let showMenuBarIcon = defaults.object(forKey: SettingsKeys.showMenuBarIcon) as? Bool ?? true
        let rawMode = defaults.string(forKey: SettingsKeys.menuBarDisplayMode) ?? MenuBarMode.currentEvent.rawValue
        let mode = MenuBarMode(rawValue: rawMode) ?? .currentEvent
        return showMenuBarIcon || mode != .none
    }

    /// Checks whether a calendar is currently included in filtering.
    ///
    /// - Parameters:
    ///   - id: The EventKit calendar identifier to query.
    /// - Returns: `true` when the calendar is enabled, otherwise `false`.
    /// - Note: This reads persisted settings and does not trigger any refresh by itself.
    func isCalendarEnabled(id: String) -> Bool {
        !disabledCalendarIDSet.contains(id)
    }

    /// Toggles a calendar between enabled and disabled states.
    ///
    /// - Parameters:
    ///   - id: The EventKit calendar identifier to update.
    /// - Returns: `Void`.
    /// - Note: Persists settings and immediately refetches events, which can refresh visible UI.
    func toggleCalendar(id: String) {
        var disabled = disabledCalendarIDSet
        if disabled.contains(id) {
            disabled.remove(id)
        } else {
            disabled.insert(id)
        }

        UserDefaults.standard.set(disabled.sorted(), forKey: SettingsKeys.disabledCalendarIDs)
        fetchEvents()
    }
    
    private func setupSystemObservers() {
        let timezoneObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleTimezoneChange()
        }
        
        let dayChangedObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDayChanged()
        }

        let eventStoreChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleEventStoreChanged()
        }
        
        let wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWakeFromSleep()
        }
        
        notificationObservers = [timezoneObserver, dayChangedObserver, eventStoreChangedObserver]
        workspaceNotificationObservers = [wakeObserver]
    }
    
    private func handleTimezoneChange() {
        guard accessGranted else { return }
        store.reset()
        invalidateCalendarCache()
        lastKnownDayStart = calendar.startOfDay(for: Date())
        lastProcessedMinute = nil
        fetchTodaysEvents(referenceDate: Date())
        refreshTimerIfNeeded()
    }
    
    private func handleDayChanged() {
        guard accessGranted else { return }
        refreshForDayBoundary(referenceDate: Date())
    }
    
    private func handleWakeFromSleep() {
        guard accessGranted else { return }
        store.reset()
        invalidateCalendarCache()
        lastKnownDayStart = calendar.startOfDay(for: Date())
        lastProcessedMinute = nil
        fetchTodaysEvents(referenceDate: Date())
        refreshTimerIfNeeded()
    }

    private func handleEventStoreChanged() {
        guard accessGranted else { return }
        invalidateCalendarCache()
        fetchTodaysEvents(referenceDate: currentMinute)
    }
    
    private func refreshForDayBoundary(referenceDate: Date) {
        lastKnownDayStart = calendar.startOfDay(for: referenceDate)
        lastProcessedMinute = nil
        upcomingEvents = []
        fetchTodaysEvents(referenceDate: referenceDate)
    }
    
    private func startTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.handleMinuteTick(date)
            }
    }
    
    private func alignToNextMinuteThenStartTimer() {
        alignmentCancellable?.cancel()
        
        let now = Date()
        let minuteStart = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        guard let nextMinute = calendar.date(byAdding: .minute, value: 1, to: minuteStart) else {
            handleMinuteTick(now)
            startTimer()
            return
        }
        
        let initialDelay = max(0.0, nextMinute.timeIntervalSince(now))
        guard initialDelay > 0.01 else {
            handleMinuteTick(nextMinute)
            startTimer()
            return
        }
        
        alignmentCancellable = Timer.publish(every: initialDelay, on: .main, in: .common)
            .autoconnect()
            .prefix(1)
            .sink { [weak self] date in
                self?.handleMinuteTick(date)
                self?.startTimer()
            }
    }
    
    private func stopTimer() {
        alignmentCancellable?.cancel()
        alignmentCancellable = nil
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    private func refreshTimerIfNeeded() {
        guard accessGranted, refreshEnabled else {
            stopTimer()
            return
        }
        alignToNextMinuteThenStartTimer()
    }
    
    /// Requests calendar authorization and updates local state from the result.
    ///
    /// - Parameters: None.
    /// - Returns: `Void`.
    /// - Warning: May present a system permission prompt and asynchronously mutate published properties.
    func requestAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        
        if #available(macOS 14.0, *) {
            switch status {
            case .notDetermined:
                store.requestFullAccessToEvents { [weak self] granted, _ in
                    DispatchQueue.main.async {
                        self?.handleAccessUpdate(granted: granted)
                    }
                }
            case .fullAccess, .authorized:
                handleAccessUpdate(granted: true)
            case .writeOnly, .restricted, .denied:
                handleAccessUpdate(granted: false)
            @unknown default:
                handleAccessUpdate(granted: false)
            }
        } else {
            switch status {
            case .notDetermined:
                store.requestAccess(to: .event) { [weak self] granted, _ in
                    DispatchQueue.main.async {
                        self?.handleAccessUpdate(granted: granted)
                    }
                }
            case .authorized, .fullAccess:
                handleAccessUpdate(granted: true)
            case .writeOnly, .restricted, .denied:
                handleAccessUpdate(granted: false)
            @unknown default:
                handleAccessUpdate(granted: false)
            }
        }
    }
    
    private func handleAccessUpdate(granted: Bool) {
        accessGranted = granted
        
        if granted {
            lastProcessedMinute = nil
            lastKnownDayStart = calendar.startOfDay(for: Date())
            fetchTodaysEvents(referenceDate: Date())
            refreshTimerIfNeeded()
            return
        }
        
        stopTimer()
        availableCalendars = []
        upcomingEvents = []
        invalidateCalendarCache()
        currentMinute = Date()
        lastEventsFetchAt = nil
        updateMenuBarTitle()
    }
    
    /// Opens macOS System Settings directly to Calendar privacy permissions.
    ///
    /// - Parameters: None.
    /// - Returns: `Void`.
    /// - Note: Launches an external system URL and shifts focus away from the app.
    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendar") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
    
    /// Opens a calendar event in the Calendar app using a deep link or timestamp fallback.
    ///
    /// - Parameters:
    ///   - event: The event to open in Calendar.
    /// - Returns: `Void`.
    /// - Note: Closes the menu popover and launches Calendar, which changes app focus.
    func openEventInCalendar(event: EKEvent) {
        closeMenuBarPopoverIfNeeded()
        
        if let externalID = event.calendarItemExternalIdentifier,
           !externalID.isEmpty,
           let encodedID = externalID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let deepLinkURL = URL(string: "ical://ekevent/\(encodedID)"),
           NSWorkspace.shared.open(deepLinkURL) {
            return
        }
        
        let timestamp = Int(event.startDate.timeIntervalSinceReferenceDate)
        guard let fallbackURL = URL(string: "calshow:\(timestamp)") else { return }
        NSWorkspace.shared.open(fallbackURL)
    }
    
    private func closeMenuBarPopoverIfNeeded() {
        NSApp.keyWindow?.performClose(nil)
    }
    
    /// Handles minute-aligned ticks used for countdown updates and periodic refetching.
    ///
    /// - Parameters:
    ///   - date: The timestamp to process, defaulting to the current time.
    /// - Returns: `Void`.
    /// - Note: Updates published state and can trigger event refetching, causing visible UI refreshes.
    func handleMinuteTick(_ date: Date = Date()) {
        let minuteStart = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        let dayStart = calendar.startOfDay(for: minuteStart)
        if dayStart != lastKnownDayStart {
            refreshForDayBoundary(referenceDate: minuteStart)
            return
        }
        guard minuteStart != lastProcessedMinute else { return }
        lastProcessedMinute = minuteStart
        currentMinute = minuteStart
        updateMenuBarTitle(now: minuteStart)
        
        if shouldPerformPeriodicRefresh(at: minuteStart) {
            fetchTodaysEvents(referenceDate: minuteStart)
        }
    }
    
    /// Fetches events for the configured date window and updates observable state.
    ///
    /// - Parameters:
    ///   - referenceDate: The anchor date used to calculate today and the fetch range.
    /// - Returns: `Void`.
    /// - Note: Reads EventKit, updates published collections, and refreshes menu bar title text.
    func fetchTodaysEvents(referenceDate: Date = Date()) {
        guard accessGranted else { return }

        let now = referenceDate
        let allCalendars = sortedCalendars()
        let disabled = disabledCalendarIDSet
        let calendars = allCalendars.filter { !disabled.contains($0.calendarIdentifier) }

        let startOfDay = calendar.startOfDay(for: now)
        let savedDays = UserDefaults.standard.integer(forKey: SettingsKeys.daysInAdvance)
        let daysInAdvance = max(1, savedDays == 0 ? 3 : savedDays)
        guard let endDate = calendar.date(byAdding: .day, value: daysInAdvance, to: startOfDay) else { return }

        let events: [EKEvent]
        if calendars.isEmpty {
            events = []
        } else {
            let predicate = store.predicateForEvents(withStart: startOfDay, end: endDate, calendars: calendars)
            events = store.events(matching: predicate)
        }

        let sortedEvents = events.sorted {
            if $0.isAllDay && !$1.isAllDay { return true }
            if !$0.isAllDay && $1.isAllDay { return false }
            return $0.startDate < $1.startDate
        }

        availableCalendars = allCalendars
        lastKnownDayStart = calendar.startOfDay(for: now)
        upcomingEvents = sortedEvents
        currentMinute = now
        lastEventsFetchAt = now
        updateMenuBarTitle(now: now)
    }
    
    /// Convenience wrapper that refetches events using the current date.
    ///
    /// - Parameters: None.
    /// - Returns: `Void`.
    /// - Note: Equivalent to calling `fetchTodaysEvents(referenceDate:)` with `Date()`.
    func fetchEvents() {
        fetchTodaysEvents(referenceDate: Date())
    }
    
    /// Truncates menu bar titles to a safe character limit.
    ///
    /// - Parameters:
    ///   - title: The original title string to display.
    ///   - limit: The maximum character count before appending an ellipsis.
    /// - Returns: A title shortened to the configured limit, or an empty string when the limit is zero.
    /// - Note: Pure formatting logic; it does not mutate view model state directly.
    func truncateTitle(_ title: String, limit: Int) -> String {
        let safeLimit = max(0, limit)
        guard safeLimit > 0 else { return "" }
        guard title.count > safeLimit else { return title }
        return String(title.prefix(safeLimit)) + "..."
    }
    
    /// Recomputes the menu bar title from mode, time context, and event data.
    ///
    /// - Parameters:
    ///   - now: The reference time used for active/upcoming event calculations.
    /// - Returns: `Void`.
    /// - Note: Mutates `menuBarTitle`, which triggers a menu bar label update in SwiftUI.
    func updateMenuBarTitle(now: Date = Date()) {
        let savedModeString = UserDefaults.standard.string(forKey: SettingsKeys.menuBarDisplayMode) ?? MenuBarMode.currentEvent.rawValue
        let mode = MenuBarMode(rawValue: savedModeString) ?? .currentEvent
        let savedCharacterLimit = UserDefaults.standard.integer(forKey: SettingsKeys.menuBarCharacterLimit)
        let characterLimit = savedCharacterLimit == 0 ? 20 : max(5, min(50, savedCharacterLimit))
        
        guard mode != .none else {
            if menuBarTitle != "" {
                menuBarTitle = ""
            }
            return
        }

        guard accessGranted else {
            let deniedTitle = "Grant Access"
            if menuBarTitle != deniedTitle {
                menuBarTitle = deniedTitle
            }
            return
        }
        
        func formatTime(_ mins: Int) -> String {
            let hours = mins / 60
            let remainder = mins % 60
            return hours > 0 ? "\(hours)h \(remainder)m" : "\(mins)m"
        }
        
        func roundedMinutes(from startDate: Date, to endDate: Date) -> Int {
            let seconds = calendar.dateComponents([.second], from: startDate, to: endDate).second ?? 0
            return max(0, Int((Double(seconds) / 60.0).rounded()))
        }

        let activeEvent = upcomingEvents.first { !$0.isAllDay && $0.startDate <= now && $0.endDate > now }
        let nextEvent = upcomingEvents.first { !$0.isAllDay && $0.startDate > now }

        func activeText(for event: EKEvent) -> String {
            let mins = roundedMinutes(from: now, to: event.endDate)
            let title = truncateTitle(event.title ?? "Event", limit: characterLimit)
            return "\(title) \(formatTime(mins)) left"
        }

        func nextText(for event: EKEvent) -> String {
            let mins = roundedMinutes(from: now, to: event.startDate)
            let title = truncateTitle(event.title ?? "Event", limit: characterLimit)
            return "\(title) in \(formatTime(mins))"
        }
        
        var nextTitle = ""

        switch mode {
        case .none:
            nextTitle = ""
        case .currentEvent:
            if let activeEvent {
                nextTitle = activeText(for: activeEvent)
            } else if let nextEvent {
                // Fallback keeps title dynamic even when nothing is currently running.
                nextTitle = nextText(for: nextEvent)
            } else {
                nextTitle = ""
            }
        case .upcomingEvent:
            if let nextEvent {
                nextTitle = nextText(for: nextEvent)
            } else if let activeEvent {
                // Fallback avoids showing only the icon when no future event exists.
                nextTitle = activeText(for: activeEvent)
            } else {
                nextTitle = ""
            }
        }
        
        if menuBarTitle != nextTitle {
            menuBarTitle = nextTitle
        }
    }

    private func shouldPerformPeriodicRefresh(at now: Date) -> Bool {
        guard let lastEventsFetchAt else { return true }
        return now.timeIntervalSince(lastEventsFetchAt) >= periodicRefreshInterval
    }

    private func migrateLegacyDisabledCalendarIDsIfNeeded() {
        let defaults = UserDefaults.standard
        if let legacyValue = defaults.string(forKey: SettingsKeys.disabledCalendarIDs),
           !legacyValue.isEmpty {
            let migrated = legacyValue
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            defaults.set(migrated, forKey: SettingsKeys.disabledCalendarIDs)
        }
    }

    private func sortedCalendars() -> [EKCalendar] {
        if isCalendarCacheValid {
            return cachedSortedCalendars
        }

        let calendars = store.calendars(for: .event)
            .sorted { lhs, rhs in
                let sourceCompare = lhs.source.title.localizedCaseInsensitiveCompare(rhs.source.title)
                if sourceCompare == .orderedSame {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return sourceCompare == .orderedAscending
            }

        cachedSortedCalendars = calendars
        isCalendarCacheValid = true
        return calendars
    }

    private func invalidateCalendarCache() {
        cachedSortedCalendars = []
        isCalendarCacheValid = false
    }
}
