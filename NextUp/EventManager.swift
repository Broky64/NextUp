import Foundation
import EventKit
import Combine

class EventManager: ObservableObject {
    private let store = EKEventStore()
    
    // On passe d'un seul événement à un tableau d'événements
    @Published var upcomingEvents: [EKEvent] = []
    @Published var accessGranted = false
    
    init() {
        requestAccess()
    }
    
    func requestAccess() {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.accessGranted = granted
                    if granted { self?.fetchUpcomingEvents() }
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.accessGranted = granted
                    if granted { self?.fetchUpcomingEvents() }
                }
            }
        }
    }
    
    func fetchUpcomingEvents() {
        let calendars = store.calendars(for: .event)
        let now = Date()
        
        // On cherche jusqu'à la fin de la journée actuelle (23:59)
        let calendar = Calendar.current
        guard let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) else { return }
        
        let predicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: calendars)
        let events = store.events(matching: predicate)
        
        DispatchQueue.main.async {
            // On filtre, on trie, et on garde les 6 prochains événements maximum
            self.upcomingEvents = events
                .filter { !$0.isAllDay && $0.startDate > now }
                .sorted { $0.startDate < $1.startDate }
                .prefix(6).map { $0 }
        }
    }
}
