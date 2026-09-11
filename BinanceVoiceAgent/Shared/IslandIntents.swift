import AppIntents

/// 灵动岛「下单」:后台直接提交(Face ID 关闭时)
struct SubmitFromIslandIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "灵动岛下单"
    static var openAppWhenRun = false
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        #if !WIDGET
        await IslandFlow.shared.submitPending()
        #endif
        return .result()
    }
}

/// 灵动岛「取消」
struct CancelFromIslandIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "取消订单"
    static var openAppWhenRun = false
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        #if !WIDGET
        await IslandFlow.shared.cancelPending()
        #endif
        return .result()
    }
}
