import SwiftUI

struct SettingsView: View {
    // @AppStorage sauvegarde automatiquement la valeur sur le Mac
    // Si la valeur n'existe pas encore, elle sera "true" par défaut
    @AppStorage("showAllDayEvents") private var showAllDayEvents = true
    @AppStorage("showPastEvents") private var showPastEvents = true
    @AppStorage("showRemainingTime") private var showRemainingTime = true
    
    var body: some View {
        Form {
            Section {
                Toggle("Show All-Day Events", isOn: $showAllDayEvents)
                Toggle("Show Past Events", isOn: $showPastEvents)
                Toggle("Show Remaining Time", isOn: $showRemainingTime)
            }
        }
        .padding(20)
        .frame(width: 350, height: 160)
        .navigationTitle("NextUp Settings")
    }
}

#Preview {
    SettingsView()
}
