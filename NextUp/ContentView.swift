import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Prochain événement :")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Réunion de synchronisation")
                .font(.headline)
            
            Text("dans 45 minutes")
                .font(.title3)
                .bold()
                .foregroundColor(.blue)
            
            Divider()
            
            Button("Quitter NextUp") {
                // Commande pour fermer l'application proprement
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
        }
        .padding()
        // On fixe la taille de notre popover
        .frame(width: 250)
    }
}

#Preview {
    ContentView()
}
