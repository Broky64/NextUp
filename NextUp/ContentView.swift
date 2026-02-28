import SwiftUI
import EventKit
import Combine

struct ContentView: View {
    @StateObject private var eventManager = EventManager()
    
    // Timer léger (60 sec)
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            
            // 1. EVENT LIST AREA
            if !eventManager.accessGranted {
                Text("Calendar access required in System Settings.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding()
                    .multilineTextAlignment(.center)
            } else if !eventManager.upcomingEvents.isEmpty {
                
                // En-tête de la liste
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .foregroundColor(.secondary)
                    Text("UPCOMING TODAY")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)
                
                // Liste compacte des événements
                VStack(spacing: 2) {
                    ForEach(eventManager.upcomingEvents, id: \.eventIdentifier) { event in
                        HStack(alignment: .center, spacing: 8) {
                            // Petit point avec la couleur native du calendrier
                            Circle()
                                .fill(Color(nsColor: event.calendar.color))
                                .frame(width: 8, height: 8)
                            
                            Text(event.title)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(event.startDate, style: .time)
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        // Effet de survol pour chaque ligne
                        .background(Color.secondary.opacity(0.0))
                    }
                }
                .padding(.bottom, 6)
                
            } else {
                // Design quand la journée est finie
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.indigo)
                    Text("Done for the day")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 16)
            }
            
            Divider()
                .padding(.bottom, 6)
            
            // 2. BOTTOM MENU (SETTINGS & QUIT)
            HStack(spacing: 12) {
                Spacer()
                
                Button {
                    print("Open Settings")
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(5)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Settings")
                
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(5)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .help("Quit NextUp")
            }
            .padding(.bottom, 8)
        }
        .frame(width: 260)
        .onReceive(timer) { _ in
            eventManager.fetchUpcomingEvents()
        }
        .onAppear {
            eventManager.fetchUpcomingEvents()
        }
    }
}
