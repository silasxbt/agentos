import ActivityKit
import Foundation

struct TradeActivityAttributes: ActivityAttributes {
    enum Phase: String, Codable, Hashable { case pending, submitting, filled, failed, cancelled }

    struct ContentState: Codable, Hashable {
        var order: TradeOrder
        var phase: Phase = .pending
        var requireBiometrics = false
        var confidence: Double = 1
        var entryPrice: Double? = nil
        var orderId: String? = nil
        var message: String? = nil
    }

    var startedAt: Date
}

enum DeepLink {
    static let edit = URL(string: "binancevoice://edit")!
    static let submit = URL(string: "binancevoice://submit")!
}
