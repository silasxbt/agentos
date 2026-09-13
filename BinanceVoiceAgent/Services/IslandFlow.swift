import Foundation
import ActivityKit
import SwiftUI
import Combine

/// 灵动岛链路:快捷指令(听写 / 增强语音)→ 本类 → Live Activity → 取消 / 编辑 / 确定
@MainActor
final class IslandFlow {
    static let shared = IslandFlow()
    private let draftKey = "island.pendingDraft"
    private var activity: Activity<TradeActivityAttributes>?
    /// 增强语音:App 进程内直接录音(不切前台)
    private let recorder = SpeechService()
    private var levelSub: AnyCancellable?
    private var levelRing: [Float] = []
    private var levelDirty = false
    private var levelPump: Timer?
    static let waveBars = 28

    var requireBiometrics: Bool { UserDefaults.standard.bool(forKey: "requireBiometrics") }

    var pendingDraft: TradeOrder? {
        get { UserDefaults.standard.data(forKey: draftKey).flatMap { try? JSONDecoder().decode(TradeOrder.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: draftKey) }
    }

    private static var placeholder: TradeOrder {
        TradeOrder(symbol: "", side: .long, leverage: 0, marginMode: .cross, notionalUSDT: 0)
    }

    // MARK: - 增强语音:录音 → 云端 ASR → 岛上确认(全程不打开 App)

    enum FlowError: LocalizedError {
        case micDenied, cancelled
        var errorDescription: String? {
            switch self {
            case .micDenied: return "麦克风未授权,请在 设置 → Binance Voice 中打开"
            case .cancelled: return "已取消"
            }
        }
    }

    /// 一键:岛上显示「正在聆听」→ 点「停止」→ 「识别中」→ 解析 → 待确认卡片
    func listenAndParse() async throws -> (transcript: String, order: TradeOrder) {
        pendingDraft = nil
        await endCurrent(immediately: true)
        guard await recorder.requestPermissions() else {
            show(phase: .failed, order: Self.placeholder, message: FlowError.micDenied.localizedDescription)
            await endCurrent(immediately: false)
            throw FlowError.micDenied
        }
        levelRing = Array(repeating: 0, count: Self.waveBars)
        show(phase: .listening, order: Self.placeholder, levels: levelRing, recordingStartedAt: Date())
        startLevelStream()
        let url: URL
        do { url = try await recorder.recordOnce() }
        catch {
            stopLevelStream()
            NSLog("[Island] record failed: \(error.localizedDescription) cancelled=\(activityCancelled)")
            if activityCancelled {
                await endCurrent(immediately: true)
                throw FlowError.cancelled
            }
            await update(phase: .failed, order: Self.placeholder, message: "录音失败:\(error.localizedDescription)")
            await endCurrent(immediately: false)
            throw error
        }
        stopLevelStream()
        defer { try? FileManager.default.removeItem(at: url) }
        await update(phase: .transcribing, order: Self.placeholder)
        let transcript: String
        do { transcript = try await DashScopeASR().transcribe(fileURL: url) }
        catch {
            await update(phase: .failed, order: Self.placeholder, message: "转写失败:\(error.localizedDescription)")
            await endCurrent(immediately: false)
            throw error
        }
        let order = await start(transcript: transcript)
        return (transcript, order)
    }

    /// 快捷指令传入的录音文件:岛上显示转写中 → 结果
    func transcribeAndParse(fileURL: URL) async {
        pendingDraft = nil
        await endCurrent(immediately: true)
        show(phase: .transcribing, order: Self.placeholder)
        do {
            let transcript = try await DashScopeASR().transcribe(fileURL: fileURL)
            await start(transcript: transcript)
        } catch {
            await update(phase: .failed, order: Self.placeholder, message: "转写失败:\(error.localizedDescription)")
            await endCurrent(immediately: false)
        }
    }

    private var activityCancelled = false

    /// 录音音量 → 每 0.25s 推一次到 Live Activity(波形动画)
    private func startLevelStream() {
        levelSub = recorder.$level.sink { [weak self] l in
            guard let self else { return }
            levelRing.removeFirst(); levelRing.append(l); levelDirty = true
        }
        levelPump = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.levelDirty, let a = self.current, a.content.state.phase == .listening else { return }
                self.levelDirty = false
                var st = a.content.state; st.levels = self.levelRing
                await a.update(.init(state: st, staleDate: nil))
            }
        }
    }

    private func stopLevelStream() {
        levelSub?.cancel(); levelSub = nil
        levelPump?.invalidate(); levelPump = nil
    }

    /// 解析文本并在灵动岛展示待确认订单(全局语音入口 / 增强语音转写后)
    @discardableResult
    func start(transcript: String) async -> TradeOrder {
        let r = CommandParser().parse(transcript)
        pendingDraft = r.order
        if current != nil {
            await update(phase: .pending, order: r.order, confidence: r.confidence)
        } else {
            await endCurrent(immediately: true)
            show(phase: .pending, order: r.order, confidence: r.confidence)
        }
        return r.order
    }

    private func show(phase: TradeActivityAttributes.Phase, order: TradeOrder, confidence: Double = 1,
                      levels: [Float] = [], recordingStartedAt: Date? = nil, message: String? = nil) {
        activityCancelled = false
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { NSLog("[Island] activities disabled"); return }
        let state = TradeActivityAttributes.ContentState(order: order, phase: phase,
                                                         requireBiometrics: requireBiometrics, confidence: confidence,
                                                         message: message, levels: levels, recordingStartedAt: recordingStartedAt)
        do {
            activity = try Activity.request(attributes: TradeActivityAttributes(startedAt: Date()),
                                            content: .init(state: state, staleDate: Date().addingTimeInterval(600)))
            NSLog("[Island] requested id=%@ phase=%@", activity?.id ?? "nil", phase.rawValue)
        } catch { NSLog("[Island] request failed: %@", String(describing: error)) }
    }

    /// 灵动岛「确定」(Face ID 关闭)/ App 内 Face ID 通过后调用 → 立刻推送成功/失败通知
    /// 灵动岛「确定」:卡片立即消失,后台下单,成功/失败立刻以通知弹出
    func submitPending() async {
        guard let order = pendingDraft else { return }
        pendingDraft = nil
        await endCurrent(immediately: true)
        do {
            let filled = try await AppState.shared.orders.submit(order)
            NotificationService.shared.notifyFilled(filled)
            NSLog("[Island] submitted ok #\(filled.orderId)")
        } catch {
            NotificationService.shared.notifyFailed(order, reason: error.localizedDescription)
            NSLog("[Island] submit failed: \(error.localizedDescription)")
        }
    }

    /// 灵动岛「完成」:手动结束录音,立即进入转写
    func finishRecording() async {
        guard recorder.isListening else { return }
        recorder.finish()
    }

    /// 灵动岛「取消」:录音中则停止录音;待确认则撤单
    func cancelPending() async {
        if recorder.isListening || recorder.isTranscribing {
            activityCancelled = true
            stopLevelStream()
            recorder.cancel()
        }
        if let order = pendingDraft { await update(phase: .cancelled, order: order) }
        pendingDraft = nil
        await endCurrent(immediately: false)
    }

    /// 用户在灵动岛点了「编辑」→ App 接管,字段已回填,岛上活动结束
    func takeOverInApp() -> TradeOrder? {
        let d = pendingDraft
        Task { await endCurrent(immediately: true) }
        return d
    }

    private var current: Activity<TradeActivityAttributes>? {
        activity ?? Activity<TradeActivityAttributes>.activities.first
    }

    private func update(phase: TradeActivityAttributes.Phase, order: TradeOrder, confidence: Double? = nil,
                        entry: Double? = nil, orderId: String? = nil, message: String? = nil) async {
        guard let activity = current else { return }
        var s = activity.content.state
        s.phase = phase; s.order = order; s.entryPrice = entry; s.orderId = orderId; s.message = message
        if let confidence { s.confidence = confidence }
        s.requireBiometrics = requireBiometrics
        if phase != .listening { s.levels = []; s.recordingStartedAt = nil }
        // 转写完成→待确认:带 alert 更新,让灵动岛重新展开成大窗口(系统在长时间录音后会自动收成小胶囊)
        if phase == .pending {
            let alert = AlertConfiguration(title: "语音已识别", body: LocalizedStringResource(stringLiteral: order.orderedSummary), sound: .default)
            await activity.update(.init(state: s, staleDate: nil), alertConfiguration: alert)
        } else {
            await activity.update(.init(state: s, staleDate: nil))
        }
    }

    private func endCurrent(immediately: Bool) async {
        for a in Activity<TradeActivityAttributes>.activities {
            // 保留最终状态(已成交/已取消)几秒,让用户看到结果
            await a.end(a.content, dismissalPolicy: immediately ? .immediate : .after(Date().addingTimeInterval(5)))
        }
        activity = nil
    }
}
