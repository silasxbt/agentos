import ActivityKit
import Foundation

struct TradeActivityAttributes: ActivityAttributes {
    enum Phase: String, Codable, Hashable { case listening, transcribing, pending, submitting, filled, failed, cancelled }

    struct ContentState: Codable, Hashable {
        var order: TradeOrder
        var phase: Phase = .pending
        var requireBiometrics = false
        var confidence: Double = 1
        var entryPrice: Double? = nil
        var orderId: String? = nil
        var message: String? = nil
        /// 录音阶段:最近 N 帧音量(0~1),驱动灵动岛波形
        var levels: [Float] = []
        var recordingStartedAt: Date? = nil

        /// 录音 / 转写阶段,还没有订单内容
        var isPreOrder: Bool { phase == .listening || phase == .transcribing }
    }

    var startedAt: Date
}

enum DeepLink {
    static let edit = URL(string: "binancevoice://edit")!
    static let submit = URL(string: "binancevoice://submit")!
}
