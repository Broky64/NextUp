/// `test_settings.swift` is a lightweight view harness in the View layer.
/// It validates settings-window activation behavior outside the main app scene.
import SwiftUI

/// Minimal test view that opens the app settings interface.
struct TestView: View {
    @Environment(\.openSettings) private var openSettings

    /// Builds a button used to trigger settings-window activation.
    ///
    /// - Returns: A button that opens settings and activates the app process.
    /// - Note: Tapping the button can bring the app to the foreground.
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
