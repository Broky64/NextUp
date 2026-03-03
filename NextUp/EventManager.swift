import Foundation
import EventKit
import Combine
import AppKit
import SwiftUI

enum MenuBarMode: String, CaseIterable {
    case none
    case currentEvent
    case upcomingEvent
}

enum SettingsKeys {
    static let showMenuBarIcon = "showMenuBarIcon"
    static let menuBarDisplayMode = "menuBarDisplayMode"
    static let menuBarCharacterLimit = "menuBarCharacterLimit"
    static let daysInAdvance = "daysInAdvance"
    static let disabledCalendarIDs = "disabledCalendarIDs"
    static let showAllDayEvents = "showAllDayEvents"
    static let showPastEvents = "showPastEvents"
    static let fontSizeOffset = "fontSizeOffset"
    static let remainingTimeColor = "remainingTimeColor"
}

final class EventManager: ObservableObject {
    static let shared = EventManager()
    
    private let store = EKEventStore()
    
    @Published var upcomingEvents: [EKEvent] = []
    @Published var availableCalendars: [EKCalendar] = []
    @Published var accessGranted = false
    @Published var menuBarTitle: String = ""
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

    var enabledCalendars: [EKCalendar] {
        let disabled = disabledCalendarIDSet
        return availableCalendars.filter { !disabled.contains($0.calendarIdentifier) }
    }
    
    func setRefreshEnabled(_ enabled: Bool) {
        refreshEnabled = enabled
        refreshTimerIfNeeded()
    }
    
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

    func isCalendarEnabled(id: String) -> Bool {
        !disabledCalendarIDSet.contains(id)
    }

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
    
    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendar") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
    
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
    
    func fetchEvents() {
        fetchTodaysEvents(referenceDate: Date())
    }
    
    func truncateTitle(_ title: String, limit: Int) -> String {
        let safeLimit = max(0, limit)
        guard safeLimit > 0 else { return "" }
        guard title.count > safeLimit else { return title }
        return String(title.prefix(safeLimit)) + "..."
    }
    
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
