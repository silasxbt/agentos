import AppIntents
import SwiftUI

/// 绑定到 iPhone Action Button(设置 → 操作按钮 → 快捷指令 → "语音下单")
struct StartVoiceTradeIntent: AppIntent {
    static var title: LocalizedStringResource = "语音下单"
    static var description = IntentDescription("打开 Binance Voice 并立即开始听写交易指令")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.triggerListening()
        return .result()
    }
}

struct BinanceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartVoiceTradeIntent(),
                    phrases: ["用\(.applicationName)下单", "\(.applicationName)语音交易", "Voice trade in \(.applicationName)"],
                    shortTitle: "语音下单",
                    systemImageName: "waveform.circle.fill")
    }
    static var shortcutTileColor: ShortcutTileColor = .yellow
}
