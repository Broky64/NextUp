import SwiftUI

@main
struct NextUpApp: App {
    var body: some Scene {
        // MenuBarExtra crée l'icône dans la barre des menus
        MenuBarExtra("NextUp", systemImage: "calendar.badge.clock") {
            ContentView()
        }
        // Le style .window permet d'afficher une belle vue SwiftUI (popover) au clic
        .menuBarExtraStyle(.window)
    }
}
