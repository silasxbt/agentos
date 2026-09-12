import AppIntents
import SwiftUI

// 三条路径:
// 1. 全局语音  VoiceTradeIntent          快捷指令「听写文本」(Apple 听写)→ 文本 → 灵动岛,不打开 App
// 2. 内置语音  StartVoiceTradeIntent     打开 App,App 内录音 → Qwen ASR → 确认页
// 3. 增强语音  EnhancedVoiceTradeIntent  快捷指令「录制音频」→ 音频文件 → 后台 Qwen ASR → 灵动岛,不打开 App

/// 全局语音:快捷指令 = 「听写文本」→ 本 Intent → 灵动岛确认
/// 绑定到 Action Button 后,在 Coinglass / TradingView 等任意界面按键即可。
struct VoiceTradeIntent: AppIntent {
    static let title: LocalizedStringResource = "全局语音下单(Apple 听写)"
    static let description = IntentDescription("接收「听写文本」的交易指令,解析后在灵动岛确认,不打开 App")
    static let openAppWhenRun = false

    /// 可选:为空时(例如 Action Button 直接触发)由系统弹出输入框/语音请求。
    /// App Shortcut 必须能零输入运行,否则绑定 Action Button 会报 "Something went wrong"。
    @Parameter(title: "交易指令", requestValueDialog: "请说出交易指令,例如:做多比特币 十倍 全仓 200U")
    var command: String?

    static var parameterSummary: some ParameterSummary { Summary("解析并下单 \(\.$command)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text0 = command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let transcript = text0.isEmpty ? try await $command.requestValue("请说出交易指令,例如:做多比特币 十倍 全仓 200U") : text0
        let order = await IslandFlow.shared.start(transcript: transcript)
        let missing = order.missingFields
        let text = missing.isEmpty ? "已识别:\(order.summary)。请在灵动岛确认。" : "缺少\(missing.joined(separator: "、")),请在灵动岛点修改补全。"
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

/// 增强语音:快捷指令「录制音频」→ 音频文件 → DashScope Qwen ASR → 灵动岛,不打开 App
struct EnhancedVoiceTradeIntent: AppIntent {
    static let title: LocalizedStringResource = "增强语音下单(Qwen 转写)"
    static let description = IntentDescription("接收「录制音频」的录音文件,用 Qwen 云端转写后在灵动岛确认,不打开 App")
    static let openAppWhenRun = false

    @Parameter(title: "录音文件", description: "来自快捷指令「录制音频」动作的输出", supportedTypeIdentifiers: ["public.audio"])
    var audio: IntentFile?

    static var parameterSummary: some ParameterSummary { Summary("用 Qwen 转写 \(\.$audio) 并下单") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let audio else {
            return .result(dialog: "请在快捷指令中先添加「录制音频」动作,并把录音传给本动作。")
        }
        let ext = (audio.filename as NSString).pathExtension.isEmpty ? "m4a" : (audio.filename as NSString).pathExtension
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shortcut_\(UUID().uuidString.prefix(8)).\(ext)")
        try audio.data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let transcript: String
        do { transcript = try await DashScopeASR().transcribe(fileURL: url) }
        catch { return .result(dialog: IntentDialog(stringLiteral: "转写失败:\(error.localizedDescription)")) }
        let order = await IslandFlow.shared.start(transcript: transcript)
        let missing = order.missingFields
        let text = missing.isEmpty ? "Qwen 识别:\(transcript)。请在灵动岛确认。" : "识别到「\(transcript)」,缺少\(missing.joined(separator: "、")),请在灵动岛点修改补全。"
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

/// 内置语音:打开 App,App 内录音 → Qwen ASR → 确认页
struct StartVoiceTradeIntent: AppIntent {
    static let title: LocalizedStringResource = "内置语音下单(打开 App)"
    static let description = IntentDescription("打开 Binance Voice 并立即开始录音,由 App 内 Qwen 转写")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.triggerListening()
        return .result()
    }
}

struct TradeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartVoiceTradeIntent(),
                    phrases: ["打开\(.applicationName)", "用\(.applicationName)下单", "\(.applicationName)语音交易"],
                    shortTitle: "内置语音", systemImageName: "mic.circle.fill")
        AppShortcut(intent: VoiceTradeIntent(),
                    phrases: ["\(.applicationName)全局语音下单"],
                    shortTitle: "全局语音", systemImageName: "waveform.circle.fill")
        AppShortcut(intent: EnhancedVoiceTradeIntent(),
                    phrases: ["\(.applicationName)增强语音下单"],
                    shortTitle: "增强语音", systemImageName: "sparkles")
    }
    static let shortcutTileColor: ShortcutTileColor = .yellow
}
