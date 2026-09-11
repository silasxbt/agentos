import Foundation

enum TradeSide: String, Codable, CaseIterable, Identifiable {
    case long, short
    var id: String { rawValue }
    var label: String { self == .long ? "做多" : "做空" }
    var labelEN: String { self == .long ? "Long" : "Short" }
    var short: String { self == .long ? "多" : "空" }
}

enum MarginMode: String, Codable, CaseIterable, Identifiable {
    case cross, isolated
    var id: String { rawValue }
    var label: String { self == .cross ? "全仓" : "逐仓" }
    var labelEN: String { self == .cross ? "Cross" : "Isolated" }
}

/// 止盈/止损可以是绝对价格,也可以是相对开仓价的百分比
enum PriceTarget: Codable, Hashable {
    case price(Double)
    case percent(Double)

    func resolved(entry: Double, side: TradeSide, isTakeProfit: Bool) -> Double {
        switch self {
        case .price(let p): return p
        case .percent(let pct):
            let direction: Double = (side == .long) == isTakeProfit ? 1 : -1
            return entry * (1 + direction * pct / 100)
        }
    }

    var display: String {
        switch self {
        case .price(let p): return Fmt.price(p)
        case .percent(let pct): return String(format: "%.1f%%", pct)
        }
    }
}

struct TradeOrder: Codable, Identifiable, Hashable {
    var id = UUID()
    var symbol: String                 // e.g. BTCUSDT
    var side: TradeSide
    var leverage: Int
    var marginMode: MarginMode
    var notionalUSDT: Double           // 保证金 (USDT)
    var takeProfit: PriceTarget?
    var stopLoss: PriceTarget?
    var rawTranscript: String = ""
    var createdAt = Date()

    var baseAsset: String { symbol.replacingOccurrences(of: "USDT", with: "") }

    var summary: String {
        var s = "\(side.short) \(baseAsset) \(leverage)x \(marginMode == .cross ? "全仓" : "逐仓") \(Fmt.usdt(notionalUSDT))"
        if let tp = takeProfit { s += " 止盈\(tp.display)" }
        if let sl = stopLoss { s += " 止损\(sl.display)" }
        return s
    }

    /// 解析后缺失的必填字段
    var missingFields: [String] {
        var m: [String] = []
        if symbol.isEmpty { m.append("币种") }
        if leverage < 1 { m.append("杠杆") }
        if notionalUSDT <= 0 { m.append("金额") }
        return m
    }
}

struct FilledOrder: Codable, Identifiable {
    var id = UUID()
    var order: TradeOrder
    var orderId: String
    var entryPrice: Double
    var quantity: Double
    var filledAt: Date
    var liquidationPrice: Double
}

enum Fmt {
    static func price(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = v >= 100 ? 2 : 4
        f.minimumFractionDigits = 0
        return f.string(from: v as NSNumber) ?? "\(v)"
    }
    static func usdt(_ v: Double) -> String { price(v) + " USDT" }
}
