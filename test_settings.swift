import SwiftUI

struct TestView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings") {
            openSettings()
            if #available(macOS 14.0, *) {
                NSApplication.shared.activate()
            } else {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }
}
print("Success")
