import SwiftUI
import EventKit
import Combine

struct EventGroup: Identifiable {
    let id = UUID()
    let title: String
    let events: [EKEvent]
}

struct ContentView: View {
    @ObservedObject var eventManager: EventManager
    @Environment(\.openSettings) private var openSettings
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    @AppStorage("showAllDayEvents") private var showAllDayEvents = true
    @AppStorage("showPastEvents") private var showPastEvents = true
    @AppStorage("fontSizeOffset") private var fontSizeOffset: Double = 0.0
    
    var groupedEvents: [EventGroup] {
        let now = eventManager.currentMinute
        let calendar = Calendar.current
        
        var today: [EKEvent] = []
        var tomorrow: [EKEvent] = []
        var laterGroups: [Date: [EKEvent]] = [:]
        
        for event in eventManager.upcomingEvents {
            if !showAllDayEvents && event.isAllDay { continue }
            if !showPastEvents && !event.isAllDay && event.endDate < now { continue }
            
            let startOfDay = calendar.startOfDay(for: event.startDate)
            if calendar.isDateInToday(event.startDate) {
                today.append(event)
            } else if calendar.isDateInTomorrow(event.startDate) {
                tomorrow.append(event)
            } else {
                laterGroups[startOfDay, default: []].append(event)
            }
        }
        
        var result: [EventGroup] = []
        if !today.isEmpty {
            result.append(EventGroup(title: "TODAY", events: today))
        }
        if !tomorrow.isEmpty {
            result.append(EventGroup(title: "TOMORROW", events: tomorrow))
        }
        
        for key in laterGroups.keys.sorted() {
            let formatter = DateFormatter()
            formatter.dateFormat = "E MMM d"
            result.append(EventGroup(title: formatter.string(from: key).uppercased(), events: laterGroups[key]!))
        }
        
        return result
    }
    
    

    var body: some View {
        VStack(spacing: 0) {
            if !eventManager.accessGranted {
                AccessDeniedView(fontSizeOffset: fontSizeOffset) {
                    eventManager.openSystemSettings()
                }
            } else if groupedEvents.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 24))
                        .foregroundColor(.primary.opacity(0.5))
                    Text("No upcoming events")
                        .font(.system(size: 12 + fontSizeOffset, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 32)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(groupedEvents) { group in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title)
                                    .font(.system(size: 9 + fontSizeOffset, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 2)
                                
                                ForEach(group.events, id: \.eventIdentifier) { event in
                                    EventRowView(
                                        event: event,
                                        fontSizeOffset: fontSizeOffset,
                                        currentMinute: eventManager.currentMinute,
                                        openEvent: { selectedEvent in
                                            eventManager.openEventInCalendar(event: selectedEvent)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 400)
            }
            
            VStack(spacing: 0) {
                Divider()
                    .padding(.bottom, 2)
                
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                } label: {
                    HStack {
                        Text("Settings")
                        Spacer()
                        Text("⌘,").foregroundColor(.secondary).font(.system(size: 11))
                    }
                    .font(.system(size: 12 + fontSizeOffset) )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
                
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack {
                        Text("Quit NextUp")
                        Spacer()
                        Text("⌘Q").foregroundColor(.secondary).font(.system(size: 11))
                    }
                    .font(.system(size: 12 + fontSizeOffset))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.bottom, 2)
        }
        .frame(width: 300)
        .onReceive(timer) { date in
            eventManager.handleMinuteTick(date)
        }
    }
}

struct AccessDeniedView: View {
    let fontSizeOffset: Double
    let openSystemSettings: () -> Void
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.lock.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.secondary)
            
            Text("Calendar Access Required")
                .font(.system(size: 13 + fontSizeOffset, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
            
            Text("NextUp needs permission to show your events. Please enable Calendar access in System Settings > Privacy & Security.")
                .font(.system(size: 11 + fontSizeOffset, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            
            Button("Open System Settings", action: openSystemSettings)
                .font(.system(size: 12 + fontSizeOffset, weight: .semibold, design: .rounded))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

struct EventRowView: View {
    let event: EKEvent
    let fontSizeOffset: Double
    let currentMinute: Date
    let openEvent: (EKEvent) -> Void
    
    @AppStorage("remainingTimeColor") private var remainingTimeColor: String = "Orange"
    @State private var isHovering = false
    
    var activeColor: Color {
        switch remainingTimeColor {
        case "Blue": return .blue
        case "Red": return .red
        case "Green": return .green
        case "Purple": return .purple
        case "Pink": return .pink
        default: return .orange
        }
    }
    
    private func roundedMinutes(from startDate: Date, to endDate: Date) -> Int {
        let calendar = Calendar.current
        let seconds = calendar.dateComponents([.second], from: startDate, to: endDate).second ?? 0
        return max(0, Int((Double(seconds) / 60.0).rounded()))
    }
    
    var body: some View {
        let now = currentMinute
        let isPast = !event.isAllDay && event.endDate < now
        let isActive = !event.isAllDay && event.startDate <= now && event.endDate > now
        
        Button {
            openEvent(event)
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(nsColor: event.calendar.color))
                    .frame(width: 3)
                    .padding(.vertical, 4)
                    
                if event.isAllDay {
                    Text("All Day")
                        .font(.system(size: 12 + fontSizeOffset, weight: .medium, design: .monospaced))
                        .foregroundColor(isPast ? .secondary.opacity(0.6) : .secondary)
                        .frame(width: 90, alignment: .leading)
                } else if isActive {
                    let diff = roundedMinutes(from: now, to: event.endDate)
                    let h = diff / 60
                    let m = diff % 60
                    let timeValue = h > 0 ? "\(h)h \(m)m" : "\(m) min"
                    
                    (Text(timeValue)
                        .font(.system(size: 12 + fontSizeOffset, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary) +
                     Text(" left")
                        .font(.system(size: 11 + fontSizeOffset, weight: .bold, design: .monospaced))
                        .foregroundColor(activeColor))
                        .frame(width: 90, alignment: .leading)
                } else {
                    Text(event.startDate, style: .time)
                        .font(.system(size: 12 + fontSizeOffset, weight: .medium, design: .monospaced))
                        .foregroundColor(isPast ? .secondary.opacity(0.6) : .secondary)
                        .frame(width: 90, alignment: .leading)
                }
                
                Text("·")
                    .foregroundColor(.secondary.opacity(0.5))
                    .font(.system(size: 12 + fontSizeOffset, weight: .bold))
                    
                Text(event.title)
                    .font(.system(size: 12 + fontSizeOffset, weight: .medium, design: .rounded))
                    .foregroundColor(isPast ? .secondary.opacity(0.6) : .primary)
                    .lineLimit(1)
                    
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(height: 22)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(isHovering ? Color.primary.opacity(0.08) : Color.clear)
        .cornerRadius(4)
        .padding(.horizontal, 8)
        .onHover { hovering in
            isHovering = hovering
        }
        .help("Click to open in Calendar")
    }
}
