import AppIntents
import UIKit
import SwiftUI

// 两条路径(都不打开 App,结果在灵动岛悬浮卡片确认:取消 / 编辑 / 确定):
// 1. 全局语音  VoiceTradeIntent          快捷指令「听写文本」(Apple 听写)→ 文本 → 灵动岛
// 2. 增强语音  EnhancedVoiceTradeIntent  一键:App 进程内直接录音 → 内置增强识别 → 灵动岛

/// 全局语音:快捷指令 = 「听写文本」→ 本 Intent → 灵动岛确认
/// LiveActivityIntent:后台运行时才允许 Activity.request(否则报 visibility)
struct VoiceTradeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "全局语音下单(Apple 听写)"
    static let description = IntentDescription("接收「听写文本」的交易指令,解析后在灵动岛确认,不打开 App")
    static let openAppWhenRun = false

    /// 可选:为空时(例如 Action Button 直接触发)由系统弹出输入框/语音请求。
    /// App Shortcut 必须能零输入运行,否则绑定 Action Button 会报 "Something went wrong"。
    @Parameter(title: "交易指令", requestValueDialog: "请说出交易指令,例如:做多比特币 十倍 全仓 200U")
    var command: String?

    static var parameterSummary: some ParameterSummary { Summary("解析并下单 \(\.$command)") }

    /// 不返回 dialog:结果只在灵动岛卡片上展示,避免快捷指令再弹一个系统弹窗
    @MainActor
    func perform() async throws -> some IntentResult {
        let text0 = command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let transcript = text0.isEmpty ? try await $command.requestValue("请说出交易指令,例如:做多比特币 十倍 全仓 200U") : text0
        await IslandFlow.shared.start(transcript: transcript)
        return .result()
    }
}

/// 增强语音:一键触发。App 进程内后台录音(不切到 App)→ 内置增强识别 → 灵动岛 取消/编辑/下单。
/// 兼容:若快捷指令里接了「录制音频」的输出,则直接转写该文件。
struct EnhancedVoiceTradeIntent: LiveActivityIntent, ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "增强语音下单"
    static let description = IntentDescription("一键录音,由 App 内置增强识别转写,结果在灵动岛确认,不打开 App")
    static let openAppWhenRun = false

    @Parameter(title: "录音文件(可选)", description: "留空则直接录音;也可接「录制音频」的输出", supportedTypeIdentifiers: ["public.audio"])
    var audio: IntentFile?

    static var parameterSummary: some ParameterSummary { Summary("增强语音下单 \(\.$audio)") }

    /// 不返回 dialog:录音 / 转写 / 结果 / 错误全部只在灵动岛卡片上展示
    @MainActor
    func perform() async throws -> some IntentResult {
        if let audio {
            let ext = (audio.filename as NSString).pathExtension.isEmpty ? "m4a" : (audio.filename as NSString).pathExtension
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("shortcut_\(UUID().uuidString.prefix(8)).\(ext)")
            try audio.data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            await IslandFlow.shared.transcribeAndParse(fileURL: url)
            return .result()
        }
        // 真机限制:App 在后台时系统不允许开启麦克风(模拟器不校验)。
        // 快捷指令拉起的 App 处于后台,先切到前台再开始录音;录音开始后回桌面/锁屏,灵动岛常驻。
        if UIApplication.shared.applicationState != .active {
            try await requestToContinueInForeground()
        }
        await IslandFlow.shared.beginListening()
        return .result()
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
