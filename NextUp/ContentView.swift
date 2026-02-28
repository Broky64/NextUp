import SwiftUI
import EventKit
import Combine

struct ContentView: View {
    @StateObject private var eventManager = EventManager()
    
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            
            if !eventManager.accessGranted {
                Text("Calendar access required in System Settings.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding()
                    .multilineTextAlignment(.center)
            } else if !eventManager.todaysEvents.isEmpty {
                
                // HEADER
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .foregroundColor(.secondary)
                    Text("TODAY")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)
                
                // LISTE DES ÉVÉNEMENTS
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(eventManager.todaysEvents, id: \.eventIdentifier) { event in
                            
                            // On ne grise pas les all-day tant que la journée n'est pas finie
                            let isPast = !event.isAllDay && event.endDate < Date()
                            
                            HStack(alignment: .center, spacing: 8) {
                                Circle()
                                    .fill(Color(nsColor: event.calendar.color))
                                    .frame(width: 8, height: 8)
                                    .opacity(isPast ? 0.3 : 1.0)
                                
                                Text(event.title)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .lineLimit(1)
                                    .foregroundColor(isPast ? .secondary : .primary)
                                
                                Spacer()
                                
                                // GESTION DU TEXTE "ALL DAY" ou de l'heure
                                if event.isAllDay {
                                    Text("All Day")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15))
                                        .cornerRadius(4)
                                } else {
                                    Text(event.startDate, style: .time)
                                        .font(.system(size: 12, weight: .regular, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .opacity(isPast ? 0.5 : 1.0)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(.bottom, 6)
                }
                .frame(maxHeight: 300)
                
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                    Text("No events today")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 16)
            }
            
            Divider()
                .padding(.bottom, 6)
            
            // BOTTOM MENU
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
            eventManager.fetchTodaysEvents()
        }
        .onAppear {
            eventManager.fetchTodaysEvents()
        }
    }
}
