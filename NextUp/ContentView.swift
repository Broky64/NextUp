import SwiftUI
import EventKit
import Combine

struct ContentView: View {
    // On initialise notre gestionnaire
    @StateObject private var eventManager = EventManager()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !eventManager.accessGranted {
                Text("Veuillez autoriser l'accès au calendrier.")
                    .foregroundColor(.orange)
            } else if let event = eventManager.nextEvent {
                // Si on a un événement, on l'affiche
                Text("Prochain événement :")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(event.title)
                    .font(.headline)
                    .lineLimit(1)
                
                // Formatage simple de l'heure
                Text(event.startDate, style: .time)
                    .font(.title3)
                    .bold()
                    .foregroundColor(.blue)
            } else {
                // Si la journée est finie
                Text("Aucun événement à venir !")
                    .font(.headline)
                    .foregroundColor(.green)
            }
            
            Divider()
            
            HStack {
                Button("Rafraîchir") {
                    eventManager.fetchNextEvent()
                }
                .buttonStyle(.borderless)
                
                Spacer()
                
                Button("Quitter") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }
        }
        .padding()
        .frame(width: 250)
    }
}
