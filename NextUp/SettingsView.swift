import SwiftUI

struct SettingsView: View {
    // @AppStorage sauvegarde automatiquement la valeur sur le Mac
    // Si la valeur n'existe pas encore, elle sera "true" par défaut
    @AppStorage("showAllDayEvents") private var showAllDayEvents = true
    @AppStorage("showPastEvents") private var showPastEvents = true
    @AppStorage("showRemainingTime") private var showRemainingTime = true
    @AppStorage("fontSizeOffset") private var fontSizeOffset: Double = 0.0
    
    var body: some View {
        Form {
            Section {
                Toggle("Show All-Day Events", isOn: $showAllDayEvents)
                Toggle("Show Past Events", isOn: $showPastEvents)
                Toggle("Show Remaining Time", isOn: $showRemainingTime)
            }
            
            Section {
                Picker("Text Size", selection: $fontSizeOffset) {
                    Text("Small").tag(-2.0)
                    Text("Normal").tag(0.0)
                    Text("Large").tag(2.0)
                    Text("Extra Large").tag(4.0)
                }
            }
        }
        .padding(20)
        .frame(width: 350, height: 210)
        .navigationTitle("NextUp Settings")
    }
}

#Preview {
    SettingsView()
}
