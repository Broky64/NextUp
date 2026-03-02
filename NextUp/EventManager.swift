import Foundation
import EventKit
import Combine

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
    
    private var timerCancellable: AnyCancellable?
    
    private init() {
        requestAccess()
    }
    
    func startTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchEvents()
            }
    }
    
    func requestAccess() {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.accessGranted = granted
                    if granted { 
                        self?.fetchEvents()
                        self?.startTimer()
                    }
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.accessGranted = granted
                    if granted { 
                        self?.fetchEvents()
                        self?.startTimer()
                    }
                }
            }
        }
    }
    
    func fetchEvents() {
        guard accessGranted else { return }
        let calendars = store.calendars(for: .event)
        let now = Date()
        let calendar = Calendar.current
        
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
            self.currentMinute = Date()
            self.updateMenuBarTitle(now: self.currentMinute)
        }
    }
    
    func updateMenuBarTitle(now: Date = Date()) {
        let savedModeString = UserDefaults.standard.string(forKey: "menuBarDisplayMode") ?? MenuBarMode.currentEvent.rawValue
        let mode = MenuBarMode(rawValue: savedModeString) ?? .currentEvent
        
        guard mode != .none else {
            menuBarTitle = ""
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
        
        if mode == .currentEvent {
            let activeEvent = upcomingEvents.first { !$0.isAllDay && $0.startDate <= now && $0.endDate > now }
            if let active = activeEvent {
                let mins = max(0, Int(active.endDate.timeIntervalSince(now) / 60))
                menuBarTitle = "\(formatTitle(active.title))... \(formatTime(mins)) left"
                return
            }
        } else if mode == .upcomingEvent {
            let veryNext = upcomingEvents.first { !$0.isAllDay && $0.startDate > now }
            if let next = veryNext {
                let diff = max(0, Int(next.startDate.timeIntervalSince(now) / 60))
                menuBarTitle = "\(formatTitle(next.title))... in \(formatTime(diff))"
                return
            }
        }
        
        menuBarTitle = ""
    }
}
