import SwiftUI

@main
struct BinanceVoiceAgentApp: App {
    @StateObject private var state = AppState.shared

    init() {
        NotificationService.shared.setup()
        BinanceShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
                .tint(Theme.yellow)
                .onOpenURL { AppState.shared.handle(url: $0) }
        }
    }
}

