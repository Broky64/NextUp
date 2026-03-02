import SwiftUI

struct SettingsView: View {
    @AppStorage("showAllDayEvents") private var showAllDayEvents = true
    @AppStorage("showPastEvents") private var showPastEvents = true
    @AppStorage("showRemainingTime") private var showRemainingTime = true
    @AppStorage("fontSizeOffset") private var fontSizeOffset: Double = 0.0
    @AppStorage("daysInAdvance") private var daysInAdvance: Int = 3
    
    var body: some View {
        TabView {
            Form {
                Toggle("Show All-Day Events", isOn: $showAllDayEvents)
                Toggle("Show Past Events", isOn: $showPastEvents)
                Toggle("Show Remaining Time", isOn: $showRemainingTime)
                
                Picker("Show events for", selection: $daysInAdvance) {
                    Text("Today only").tag(1)
                    Text("Next 2 Days").tag(2)
                    Text("Next 3 Days").tag(3)
                    Text("Next 7 Days").tag(7)
                    Text("Next 14 Days").tag(14)
                    Text("Next 30 Days").tag(30)
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
                    Text("Small").tag(-2.0)
                    Text("Normal").tag(0.0)
                    Text("Large").tag(2.0)
                    Text("Extra Large").tag(4.0)
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
