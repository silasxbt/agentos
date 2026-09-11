import Foundation
import ActivityKit
import SwiftUI

/// 全局触发链路:快捷指令(听写)→ 本类 → 灵动岛 Live Activity → 取消/修改/下单
@MainActor
final class IslandFlow {
    static let shared = IslandFlow()
    private let draftKey = "island.pendingDraft"
    private var activity: Activity<TradeActivityAttributes>?

    var requireBiometrics: Bool { UserDefaults.standard.bool(forKey: "requireBiometrics") }

    var pendingDraft: TradeOrder? {
        get { UserDefaults.standard.data(forKey: draftKey).flatMap { try? JSONDecoder().decode(TradeOrder.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: draftKey) }
    }

    /// 解析文本并在灵动岛展示待确认订单
    @discardableResult
    func start(transcript: String) async -> TradeOrder {
        let r = CommandParser().parse(transcript)
        pendingDraft = r.order
        await endCurrent(immediately: true)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { NSLog("[Island] activities disabled"); return r.order }
        let state = TradeActivityAttributes.ContentState(order: r.order, phase: .pending,
                                                         requireBiometrics: requireBiometrics, confidence: r.confidence)
        do {
            activity = try Activity.request(attributes: TradeActivityAttributes(startedAt: Date()),
                                            content: .init(state: state, staleDate: Date().addingTimeInterval(600)))
            NSLog("[Island] requested id=%@", activity?.id ?? "nil")
        } catch { NSLog("[Island] request failed: %@", String(describing: error)) }
        return r.order
    }

    /// 灵动岛「下单」(Face ID 关闭)/ App 内 Face ID 通过后调用
    func submitPending() async {
        guard let order = pendingDraft else { return }
        await update(phase: .submitting, order: order)
        do {
            let filled = try await AppState.shared.orders.submit(order)
            NotificationService.shared.notifyFilled(filled)
            await update(phase: .filled, order: order, entry: filled.entryPrice, orderId: filled.orderId)
        } catch {
            NotificationService.shared.notifyFailed(order, reason: error.localizedDescription)
            await update(phase: .failed, order: order, message: error.localizedDescription)
        }
        pendingDraft = nil
        await endCurrent(immediately: false)
    }

    func cancelPending() async {
        if let order = pendingDraft { await update(phase: .cancelled, order: order) }
        pendingDraft = nil
        await endCurrent(immediately: false)
    }

    /// 用户在灵动岛点了「修改」→ App 接管,岛上活动结束
    func takeOverInApp() -> TradeOrder? {
        let d = pendingDraft
        Task { await endCurrent(immediately: true) }
        return d
    }

    private var current: Activity<TradeActivityAttributes>? {
        activity ?? Activity<TradeActivityAttributes>.activities.first
    }

    private func update(phase: TradeActivityAttributes.Phase, order: TradeOrder,
                        entry: Double? = nil, orderId: String? = nil, message: String? = nil) async {
        guard let activity = current else { return }
        var s = activity.content.state
        s.phase = phase; s.order = order; s.entryPrice = entry; s.orderId = orderId; s.message = message
        await activity.update(.init(state: s, staleDate: nil))
    }

    private func endCurrent(immediately: Bool) async {
        for a in Activity<TradeActivityAttributes>.activities {
            // 保留最终状态(已成交/已取消)几秒,让用户看到结果
            await a.end(a.content, dismissalPolicy: immediately ? .immediate : .after(Date().addingTimeInterval(5)))
        }
        activity = nil
    }
}
