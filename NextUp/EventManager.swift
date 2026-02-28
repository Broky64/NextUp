import Foundation
import EventKit
import Combine

class EventManager: ObservableObject {
    private let store = EKEventStore()
    
    // @Published permet de mettre à jour l'interface automatiquement quand la valeur change
    @Published var nextEvent: EKEvent?
    @Published var accessGranted = false
    
    init() {
        requestAccess()
    }
    
    func requestAccess() {
        // Gestion de la permission selon la version de macOS
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.accessGranted = granted
                    if granted { self?.fetchNextEvent() }
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.accessGranted = granted
                    if granted { self?.fetchNextEvent() }
                }
            }
        }
    }
    
    func fetchNextEvent() {
        let calendars = store.calendars(for: .event)
        let now = Date()
        // On cherche les événements dans les 24 prochaines heures (pour économiser le CPU)
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) else { return }
        
        let predicate = store.predicateForEvents(withStart: now, end: tomorrow, calendars: calendars)
        let events = store.events(matching: predicate)
        
        // On filtre : pas d'événements sur toute la journée, et on trie par date de début
        self.nextEvent = events
            .filter { !$0.isAllDay && $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first
    }
}
