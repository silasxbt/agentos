import AppIntents

/// 灵动岛「下单」:后台直接提交(Face ID 关闭时)
struct SubmitFromIslandIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "灵动岛下单"
    static let openAppWhenRun = false
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        #if !WIDGET
        await IslandFlow.shared.submitPending()
        #endif
        return .result()
    }
}

/// 灵动岛「取消」
struct CancelFromIslandIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "取消订单"
    static let openAppWhenRun = false
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        #if !WIDGET
        await IslandFlow.shared.cancelPending()
        #endif
        return .result()
    }
}

/// 灵动岛「完成」:手动结束录音,进入转写
struct FinishRecordingFromIslandIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "结束录音"
    static let openAppWhenRun = false
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        #if !WIDGET
        await IslandFlow.shared.finishRecording()
        #endif
        return .result()
    }
}
