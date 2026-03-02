import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("showAllDayEvents") private var showAllDayEvents = true
    @AppStorage("showPastEvents") private var showPastEvents = true
    @AppStorage("showRemainingTime") private var showRemainingTime = true
    @AppStorage("fontSizeOffset") private var fontSizeOffset: Double = 0.0
    @AppStorage("daysInAdvance") private var daysInAdvance: Int = 3
    @AppStorage("remainingTimeColor") private var remainingTimeColor: String = "Orange"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    
    var body: some View {
        TabView {
            Form {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        do {
                            if launchAtLogin {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("Failed to update Launch at login: \(error.localizedDescription)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                    .onAppear {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                
                Toggle("Show All-Day Events", isOn: $showAllDayEvents)
                Toggle("Show Past Events", isOn: $showPastEvents)
                Toggle("Show Remaining Time", isOn: $showRemainingTime)
                
                Picker("Show events for", selection: $daysInAdvance) {
                    Text("Today only").tag(1)
                    Text("Next 2 Days").tag(2)
                    Text("Next 3 Days").tag(3)
                    Text("Next 7 Days").tag(7)
                }
                .onChange(of: daysInAdvance) {
                    EventManager.shared.fetchEvents()
                }
            }
            .padding(20)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            
            Form {
                Picker("Text Size", selection: $fontSizeOffset) {
                    ForEach(8..<25) { size in
                        Text("\(size) pt").tag(Double(size - 12))
                    }
                }
                
                Picker("Active Time Color", selection: $remainingTimeColor) {
                    Text("Orange").tag("Orange")
                    Text("Blue").tag("Blue")
                    Text("Red").tag("Red")
                    Text("Green").tag("Green")
                    Text("Purple").tag("Purple")
                    Text("Pink").tag("Pink")
                }
            }
            .padding(20)
            .tabItem {
                Label("Appearance", systemImage: "paintpalette")
            }
        }
        .frame(width: 400, height: 250)
    }
}

#Preview {
    SettingsView()
}
