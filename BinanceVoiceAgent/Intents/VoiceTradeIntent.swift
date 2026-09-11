import AppIntents
import SwiftUI

/// 全局语音下单(不打开 App):快捷指令 = 「听写文本」→ 本 Intent → 灵动岛确认
/// 绑定到 Action Button 后,在 Coinglass / TradingView 等任意界面按键即可。
struct VoiceTradeIntent: AppIntent {
    static var title: LocalizedStringResource = "语音下单(灵动岛)"
    static var description = IntentDescription("把听写的交易指令解析为订单,在灵动岛上确认,不打开 App")
    static var openAppWhenRun = false

    @Parameter(title: "交易指令", requestValueDialog: "请说出交易指令,例如:做多比特币 十倍 全仓 200U")
    var command: String

    static var parameterSummary: some ParameterSummary { Summary("解析并下单 \(\.$command)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let order = await IslandFlow.shared.start(transcript: command)
        let missing = order.missingFields
        let text = missing.isEmpty ? "已识别:\(order.summary)。请在灵动岛确认。" : "缺少\(missing.joined(separator: "、")),请在灵动岛点修改补全。"
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

/// 打开 App 并开始听写(App 内麦克风路径)
struct StartVoiceTradeIntent: AppIntent {
    static var title: LocalizedStringResource = "打开语音下单"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.triggerListening()
        return .result()
    }
}

struct BinanceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: VoiceTradeIntent(),
                    phrases: ["用\(.applicationName)下单", "\(.applicationName)语音交易"],
                    shortTitle: "语音下单", systemImageName: "waveform.circle.fill")
        AppShortcut(intent: StartVoiceTradeIntent(),
                    phrases: ["打开\(.applicationName)听写"],
                    shortTitle: "打开语音下单", systemImageName: "mic.circle.fill")
    }
    static var shortcutTileColor: ShortcutTileColor = .yellow
}
