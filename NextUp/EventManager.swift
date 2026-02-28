import Foundation
import EventKit
import Combine

class EventManager: ObservableObject {
    private let store = EKEventStore()
    
    // Le tableau contient maintenant tous les événements du jour
    @Published var todaysEvents: [EKEvent] = []
    @Published var accessGranted = false
    
    init() {
        requestAccess()
    }
    
    func requestAccess() {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.accessGranted = granted
                    if granted { self?.fetchTodaysEvents() }
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.accessGranted = granted
                    if granted { self?.fetchTodaysEvents() }
                }
            }
        }
    }
    
    func fetchTodaysEvents() {
            let calendars = store.calendars(for: .event)
            let now = Date()
            let calendar = Calendar.current
            
            let startOfDay = calendar.startOfDay(for: now)
            guard let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) else { return }
            
            let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: calendars)
            let events = store.events(matching: predicate)
            
            DispatchQueue.main.async {
                // J'ai retiré le filtre .filter { !$0.isAllDay }
                // Tous les événements (y compris all-day) sont maintenant affichés !
                self.todaysEvents = events
                    .sorted {
                        // On met les événements "All Day" tout en haut de la liste
                        if $0.isAllDay && !$1.isAllDay { return true }
                        if !$0.isAllDay && $1.isAllDay { return false }
                        return $0.startDate < $1.startDate
                    }
            }
        }   
}
