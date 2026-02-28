import SwiftUI
import EventKit
import Combine

struct ContentView: View {
    @StateObject private var eventManager = EventManager()
    
    // Lightweight timer ticking every 60 seconds
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            
            // 1. EVENT AREA
            if !eventManager.accessGranted {
                Text("Calendar access required in System Settings.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding()
                    .multilineTextAlignment(.center)
            } else if let event = eventManager.nextEvent {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(.blue)
                        Text("NEXT UP")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    
                    Text(event.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    
                    HStack {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                        Text(event.startDate, style: .time)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.blue)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
                .padding([.horizontal, .top], 12)
                
            } else {
                // Design when the day is over
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.largeTitle)
                        .foregroundColor(.indigo)
                    Text("Done for the day")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 20)
            }
            
            Divider()
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            // 2. BOTTOM MENU (SETTINGS & QUIT)
            HStack(spacing: 12) {
                Spacer()
                
                // Settings Button
                Button {
                    // Action for settings (to be implemented)
                    print("Open Settings")
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Settings")
                
                // Quit Button
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(6)
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
        // 3. AUTO-REFRESH TRIGGERS
        .onReceive(timer) { _ in
            eventManager.fetchNextEvent()
        }
        .onAppear {
            eventManager.fetchNextEvent()
        }
    }
}
