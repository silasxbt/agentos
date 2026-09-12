import AppIntents
import SwiftUI

// 两条路径(都不打开 App,结果在灵动岛悬浮卡片确认:取消 / 编辑 / 确定):
// 1. 全局语音  VoiceTradeIntent          快捷指令「听写文本」(Apple 听写)→ 文本 → 灵动岛
// 2. 增强语音  EnhancedVoiceTradeIntent  一键:App 进程内直接录音 → 内置 Qwen ASR → 灵动岛

/// 全局语音:快捷指令 = 「听写文本」→ 本 Intent → 灵动岛确认
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
        return .result(dialog: IntentDialog(stringLiteral: Self.dialog(for: order, transcript: nil)))
    }

    static func dialog(for order: TradeOrder, transcript: String?) -> String {
        let missing = order.missingFields
        let head = transcript.map { "识别到「\($0)」" } ?? "已识别:\(order.summary)"
        return missing.isEmpty ? "\(head)。请在灵动岛点确定下单。" : "\(head),缺少\(missing.joined(separator: "、")),请在灵动岛点编辑补全。"
    }
}

/// 增强语音:一键触发。App 进程内后台录音(不切到 App)→ 内置 Qwen ASR → 灵动岛 取消/编辑/确定。
/// 兼容:若快捷指令里接了「录制音频」的输出,则直接转写该文件。
struct EnhancedVoiceTradeIntent: AppIntent {
    static let title: LocalizedStringResource = "增强语音下单(Qwen)"
    static let description = IntentDescription("一键录音,由 App 内置的 Qwen 模型转写,结果在灵动岛确认,不打开 App")
    static let openAppWhenRun = false

    @Parameter(title: "录音文件(可选)", description: "留空则直接录音;也可接「录制音频」的输出", supportedTypeIdentifiers: ["public.audio"])
    var audio: IntentFile?

    static var parameterSummary: some ParameterSummary { Summary("增强语音下单 \(\.$audio)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let audio {
            let ext = (audio.filename as NSString).pathExtension.isEmpty ? "m4a" : (audio.filename as NSString).pathExtension
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("shortcut_\(UUID().uuidString.prefix(8)).\(ext)")
            try audio.data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let transcript: String
            do { transcript = try await DashScopeASR().transcribe(fileURL: url) }
            catch { return .result(dialog: IntentDialog(stringLiteral: "转写失败:\(error.localizedDescription)")) }
            let order = await IslandFlow.shared.start(transcript: transcript)
            return .result(dialog: IntentDialog(stringLiteral: VoiceTradeIntent.dialog(for: order, transcript: transcript)))
        }
        do {
            let (transcript, order) = try await IslandFlow.shared.listenAndParse()
            return .result(dialog: IntentDialog(stringLiteral: VoiceTradeIntent.dialog(for: order, transcript: transcript)))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        }
    }
}

struct TradeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: VoiceTradeIntent(),
                    phrases: ["\(.applicationName)全局语音下单", "用\(.applicationName)下单"],
                    shortTitle: "全局语音", systemImageName: "waveform.circle.fill")
        AppShortcut(intent: EnhancedVoiceTradeIntent(),
                    phrases: ["\(.applicationName)增强语音下单", "\(.applicationName)语音交易"],
                    shortTitle: "增强语音", systemImageName: "sparkles")
    }
    static let shortcutTileColor: ShortcutTileColor = .yellow
}
