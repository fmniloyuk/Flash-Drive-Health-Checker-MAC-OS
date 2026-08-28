import SwiftUI

@main
struct FlashScopeApp: App {
    @State private var preferences: AppPreferences
    @State private var model: AppViewModel

    init() {
        let preferences = AppPreferences()
        let services = AppServices.make()
        _preferences = State(initialValue: preferences)
        _model = State(initialValue: AppViewModel(services: services, preferences: preferences))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .tint(.teal)
                .preferredColorScheme(preferences.appearance.colorScheme)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1180, height: 780)

        Settings {
            SettingsView(preferences: preferences)
                .tint(.teal)
                .preferredColorScheme(preferences.appearance.colorScheme)
        }
    }
}
