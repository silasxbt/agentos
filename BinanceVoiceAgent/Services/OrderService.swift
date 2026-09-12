import Foundation

/// 模拟 Binance USDⓈ-M 合约下单。黑客松演示用,接口签名对齐 /fapi/v1/order,可直接替换为真实 REST 调用。
final class OrderService: ObservableObject {
    @Published private(set) var history: [FilledOrder] = []

    private static let mockPrices: [String: Double] = [
        "BTC": 67_420, "ETH": 3_512, "SOL": 158.4, "BNB": 592, "XRP": 0.62, "DOGE": 0.158, "ADA": 0.46, "DOT": 7.1,
        "LTC": 84.3, "PEPE": 0.0000112, "ATOM": 8.9, "LINK": 14.6, "AVAX": 35.2, "SUI": 1.02, "TON": 7.3, "TRX": 0.12, "ARB": 1.1, "OP": 2.4,
    ]

    /// 模拟可用保证金(USDT)。保证金超过该值即返回「可用保证金不足」,用于演示下单失败。
    static let availableBalance: Double = 1_000

    static func markPrice(_ symbol: String) -> Double? {
        mockPrices[symbol.replacingOccurrences(of: "USDT", with: "")]
    }

    enum OrderError: LocalizedError {
        case unknownSymbol, insufficientBalance, network
        var errorDescription: String? {
            switch self {
            case .unknownSymbol: return "交易对不存在"
            case .insufficientBalance: return "可用保证金不足(可用 \(Fmt.usdt(OrderService.availableBalance)))"
            case .network: return "网络超时,请重试"
            }
        }
    }

    @MainActor
    func submit(_ order: TradeOrder) async throws -> FilledOrder {
        // 1) 设置杠杆 POST /fapi/v1/leverage  2) 设置仓位模式 POST /fapi/v1/marginType  3) 市价开仓 POST /fapi/v1/order
        try await Task.sleep(for: .milliseconds(900))
        guard let mark = Self.markPrice(order.symbol) else { throw OrderError.unknownSymbol }
        guard order.notionalUSDT <= Self.availableBalance else { throw OrderError.insufficientBalance }
        let slippage = 1 + Double.random(in: -0.0004...0.0004)
        let entry = mark * slippage
        let qty = order.notionalUSDT * Double(order.leverage) / entry
        let mmr = 0.004
        let liq = order.side == .long
            ? entry * (1 - 1.0 / Double(order.leverage) + mmr)
            : entry * (1 + 1.0 / Double(order.leverage) - mmr)
        let filled = FilledOrder(order: order, orderId: String(Int.random(in: 4_000_000_000...4_999_999_999)),
                                 entryPrice: entry, quantity: qty, filledAt: Date(), liquidationPrice: liq)
        history.insert(filled, at: 0)
        return filled
    }
}
