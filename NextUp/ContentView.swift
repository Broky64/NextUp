import SwiftUI
import EventKit

struct EventGroup: Identifiable {
    let id = UUID()
    let title: String
    let events: [EKEvent]
}

struct ContentView: View {
    @EnvironmentObject private var eventManager: EventManager
    @Environment(\.openSettings) private var openSettings
    
    @AppStorage("showAllDayEvents") private var showAllDayEvents = true
    @AppStorage("showPastEvents") private var showPastEvents = true
    @AppStorage("fontSizeOffset") private var fontSizeOffset: Double = 0.0
    
    var groupedEvents: [EventGroup] {
        let now = eventManager.currentMinute
        let calendar = Calendar.current
        
        var active: [EKEvent] = []
        var today: [EKEvent] = []
        var tomorrow: [EKEvent] = []
        var laterGroups: [Date: [EKEvent]] = [:]
        
        for event in eventManager.upcomingEvents {
            if !showAllDayEvents && event.isAllDay { continue }
            if !showPastEvents && !event.isAllDay && event.endDate < now { continue }
            
            if !event.isAllDay && event.startDate <= now && event.endDate > now {
                active.append(event)
            } else if calendar.isDateInToday(event.startDate) {
                today.append(event)
            } else if calendar.isDateInTomorrow(event.startDate) {
                tomorrow.append(event)
            } else {
                let startOfDay = calendar.startOfDay(for: event.startDate)
                laterGroups[startOfDay, default: []].append(event)
            }
        }
        
        var result: [EventGroup] = []
        if !active.isEmpty {
            let earliestEnd = active.map { $0.endDate }.min() ?? now
            let diff = max(0, Int(earliestEnd.timeIntervalSince(now) / 60))
            let h = diff / 60
            let m = diff % 60
            let timeStr = h > 0 ? "\(h)h \(m)m" : "\(m) MIN"
            result.append(EventGroup(title: "ENDING IN \(timeStr.uppercased())", events: active))
        }
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
    
    var highlightedEventID: String? {
        let now = eventManager.currentMinute
        if let active = eventManager.upcomingEvents.first(where: { !$0.isAllDay && $0.startDate <= now && $0.endDate > now }) {
            return active.eventIdentifier
        }
        if let next = eventManager.upcomingEvents.first(where: { !$0.isAllDay && $0.startDate > now }) {
            return next.eventIdentifier
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if !eventManager.accessGranted {
                Text("Calendar access required.")
                    .font(.system(size: 13 + fontSizeOffset, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 32)
            } else if groupedEvents.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 24))
                        .foregroundColor(.primary.opacity(0.5))
                    Text("No upcoming events")
                        .font(.system(size: 13 + fontSizeOffset, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 32)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(groupedEvents) { group in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title)
                                    .font(.system(size: 10 + fontSizeOffset, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 2)
                                
                                ForEach(group.events, id: \.eventIdentifier) { event in
                                    EventRowView(
                                        event: event,
                                        isHighlighted: event.eventIdentifier == highlightedEventID,
                                        fontSizeOffset: fontSizeOffset
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
                    .font(.system(size: 13 + fontSizeOffset) )
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
                    .font(.system(size: 13 + fontSizeOffset))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.bottom, 2)
        }
        .frame(width: 280)
    }
}

struct EventRowView: View {
    let event: EKEvent
    let isHighlighted: Bool
    let fontSizeOffset: Double
    
    var body: some View {
        let now = Date()
        let isPast = !event.isAllDay && event.endDate < now
        
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(nsColor: event.calendar.color))
                .frame(width: 3)
                .padding(.vertical, 4)
                
            if event.isAllDay {
                Text("All Day")
                    .font(.system(size: 13 + fontSizeOffset, weight: .medium, design: .monospaced))
                    .foregroundColor(isHighlighted ? .white : (isPast ? .secondary.opacity(0.6) : .secondary))
                    .frame(width: 65, alignment: .leading)
            } else {
                Text(event.startDate, style: .time)
                    .font(.system(size: 13 + fontSizeOffset, weight: .medium, design: .monospaced))
                    .foregroundColor(isHighlighted ? .white : (isPast ? .secondary.opacity(0.6) : .secondary))
                    .frame(width: 65, alignment: .leading)
            }
            
            Text("·")
                .foregroundColor(isHighlighted ? .white.opacity(0.6) : .secondary.opacity(0.5))
                .font(.system(size: 13 + fontSizeOffset, weight: .bold))
                
            Text(event.title)
                .font(.system(size: 13 + fontSizeOffset, weight: .medium, design: .rounded))
                .foregroundColor(isHighlighted ? .white : (isPast ? .secondary.opacity(0.6) : .primary))
                .lineLimit(1)
                
            Spacer()
        }
        .frame(height: 22)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(isHighlighted ? Color.blue : Color.clear)
        .cornerRadius(4)
        .padding(.horizontal, 8)
    }
}
