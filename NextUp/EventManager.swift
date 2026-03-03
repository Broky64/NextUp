import Foundation
import EventKit
import Combine
import AppKit

enum MenuBarMode: String, CaseIterable {
    case none
    case currentEvent
    case upcomingEvent
}

class EventManager: ObservableObject {
    static let shared = EventManager()
    
    private let store = EKEventStore()
    
    @Published var upcomingEvents: [EKEvent] = []
    @Published var accessGranted = false
    @Published var menuBarTitle: String = ""
    @Published var currentMinute: Date = Date()
    
    private let calendar = Calendar.current
    private var timerCancellable: AnyCancellable?
    private var alignmentCancellable: AnyCancellable?
    private var refreshEnabled = true
    private var lastProcessedMinute: Date?
    
    private init() {
        refreshEnabled = shouldRefreshInBackground()
        requestAccess()
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
        let showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        let rawMode = defaults.string(forKey: "menuBarDisplayMode") ?? MenuBarMode.currentEvent.rawValue
        let mode = MenuBarMode(rawValue: rawMode) ?? .currentEvent
        return showMenuBarIcon || mode != .none
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
            fetchTodaysEvents(referenceDate: Date())
            refreshTimerIfNeeded()
            return
        }
        
        stopTimer()
        upcomingEvents = []
        currentMinute = Date()
        updateMenuBarTitle()
    }
    
    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendar") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
    
    func handleMinuteTick(_ date: Date = Date()) {
        let minuteStart = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        guard minuteStart != lastProcessedMinute else { return }
        lastProcessedMinute = minuteStart
        fetchTodaysEvents(referenceDate: minuteStart)
    }
    
    func fetchTodaysEvents(referenceDate: Date = Date()) {
        guard accessGranted else { return }

        // EventKit access is local to the system calendar database (no network call here).
        let calendars = store.calendars(for: .event)
        let now = referenceDate
        
        let startOfDay = calendar.startOfDay(for: now)
        let savedDays = UserDefaults.standard.integer(forKey: "daysInAdvance")
        let daysInAdvance = savedDays == 0 ? 3 : savedDays
        guard let endDate = calendar.date(byAdding: .day, value: daysInAdvance, to: startOfDay) else { return }
        
        let predicate = store.predicateForEvents(withStart: startOfDay, end: endDate, calendars: calendars)
        let events = store.events(matching: predicate)
        
        DispatchQueue.main.async {
            self.upcomingEvents = events.sorted {
                if $0.isAllDay && !$1.isAllDay { return true }
                if !$0.isAllDay && $1.isAllDay { return false }
                return $0.startDate < $1.startDate
            }
            self.currentMinute = now
            self.updateMenuBarTitle(now: now)
        }
    }
    
    func fetchEvents() {
        fetchTodaysEvents(referenceDate: Date())
    }
    
    func updateMenuBarTitle(now: Date = Date()) {
        let savedModeString = UserDefaults.standard.string(forKey: "menuBarDisplayMode") ?? MenuBarMode.currentEvent.rawValue
        let mode = MenuBarMode(rawValue: savedModeString) ?? .currentEvent
        
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
        
        func formatTitle(_ title: String?) -> String {
            let text = title ?? "Event"
            return text.count > 20 ? String(text.prefix(20)) + "..." : text
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
            return "\(formatTitle(event.title)) \(formatTime(mins)) left"
        }

        func nextText(for event: EKEvent) -> String {
            let mins = roundedMinutes(from: now, to: event.startDate)
            return "\(formatTitle(event.title)) in \(formatTime(mins))"
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
}
