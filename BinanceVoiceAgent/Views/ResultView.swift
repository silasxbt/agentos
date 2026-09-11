import SwiftUI

struct ResultView: View {
    @EnvironmentObject var state: AppState
    let filled: FilledOrder
    @State private var appear = false

    var body: some View {
        let o = filled.order
        VStack(spacing: 22) {
            Spacer(minLength: 20)
            ZStack {
                Circle().fill(Theme.green.opacity(0.15)).frame(width: 130, height: 130).scaleEffect(appear ? 1 : 0.5)
                Image(systemName: "checkmark.circle.fill").font(.system(size: 84)).foregroundStyle(Theme.green)
                    .scaleEffect(appear ? 1 : 0.3)
            }
            Text("订单已成交").font(.title.bold())
            Text("已通过系统通知推送成交回执").font(.caption).foregroundStyle(Theme.text2)

            VStack(spacing: 0) {
                line("交易对", "\(o.baseAsset)USDT 永续")
                line("方向", o.side.label, color: o.side == .long ? Theme.green : Theme.red)
                line("杠杆 / 模式", "\(o.leverage)x · \(o.marginMode.label)")
                line("开仓价", Fmt.price(filled.entryPrice))
                line("数量", String(format: "%.4f %@", filled.quantity, o.baseAsset))
                line("保证金", Fmt.usdt(o.notionalUSDT))
                if let tp = o.takeProfit { line("止盈", Fmt.price(tp.resolved(entry: filled.entryPrice, side: o.side, isTakeProfit: true)), color: Theme.green) }
                if let sl = o.stopLoss { line("止损", Fmt.price(sl.resolved(entry: filled.entryPrice, side: o.side, isTakeProfit: false)), color: Theme.red) }
                line("预估强平价", Fmt.price(filled.liquidationPrice), color: Theme.yellow)
                line("订单号", filled.orderId, last: true)
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))

            Spacer()
            Button("完成") { state.reset() }.buttonStyle(PrimaryButton())
        }
        .padding(20)
        .onAppear { withAnimation(.spring(duration: 0.6, bounce: 0.4)) { appear = true } }
    }

    private func line(_ k: String, _ v: String, color: Color = .primary, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack { Text(k).foregroundStyle(Theme.text2); Spacer(); Text(v).foregroundStyle(color).font(.body.monospacedDigit()) }
                .padding(.horizontal, 14).padding(.vertical, 11)
            if !last { Divider().overlay(Theme.card2).padding(.leading, 14) }
        }
    }
}
