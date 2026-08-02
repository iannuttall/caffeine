import AppKit
import SwiftUI

@main
struct CaffeineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: SettingsStore
    @State private var controller: AwakeController

    init() {
        let settings = SettingsStore()
        let controller = AwakeController(settings: settings)
        _settings = State(wrappedValue: settings)
        _controller = State(wrappedValue: controller)
        self.appDelegate.configure(.init(settings: settings, controller: controller))
    }

    var body: some Scene {
        Settings {
            SettingsView(
                settings: self.settings,
                controller: self.controller,
                updater: self.appDelegate.updater)
        }
        .windowResizability(.contentSize)
    }
}
