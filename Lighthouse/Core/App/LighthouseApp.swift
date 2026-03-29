import SwiftUI

@main
struct LighthouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// SwiftUI scene declaration; actual app lifecycle is delegated to AppDelegate.
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
