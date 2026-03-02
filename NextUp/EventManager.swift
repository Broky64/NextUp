import Foundation
import EventKit
import Combine

class EventManager: ObservableObject {
    static let shared = EventManager()
    
    private let store = EKEventStore()
    
    @Published var upcomingEvents: [EKEvent] = []
    @Published var accessGranted = false
    @Published var menuBarTitle: String = "NextUp"
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
    
    private func updateMenuBarTitle(now: Date) {
        let activeEvent = upcomingEvents.first { !$0.isAllDay && $0.startDate <= now && $0.endDate > now }
        if let active = activeEvent {
            let mins = max(0, Int(active.endDate.timeIntervalSince(now) / 60))
            let hours = mins / 60
            let remainder = mins % 60
            let timeStr = hours > 0 ? "\(hours)h \(remainder)m" : "\(mins) min"
            menuBarTitle = "\(active.title ?? "Event")... \(timeStr) left"
            return
        }
        
        let veryNext = upcomingEvents.first { !$0.isAllDay && $0.startDate > now }
        if let next = veryNext {
            let diff = max(0, Int(next.startDate.timeIntervalSince(now) / 60))
            let hours = diff / 60
            let remainder = diff % 60
            let timeStr = hours > 0 ? "in \(hours)h \(remainder)m" : "in \(diff)m"
            menuBarTitle = "\(next.title ?? "Event")... \(timeStr)"
            return
        }
        
        menuBarTitle = "No upcoming events"
    }
}
