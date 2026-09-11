import SwiftUI

struct ResultView: View {
    @EnvironmentObject var state: AppState
    let filled: FilledOrder
    @State private var appear = false

    var body: some View {
        let o = filled.order
        VStack(spacing: 0) {
            NavBar(title: "订单详情") { EmptyView() } trailing: {
                Button { state.reset() } label: { Image(systemName: "xmark").foregroundStyle(Theme.text) }
            }
            ScrollView {
                VStack(spacing: 12) {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(Theme.green)
                            .scaleEffect(appear ? 1 : 0.4)
                        Text("已成交").font(Theme.title)
                        Text("成交回执已通过系统通知推送").font(Theme.caption).foregroundStyle(Theme.text3)
                    }.padding(.vertical, 20)

                    // 交易对头
                    HStack(spacing: 12) {
                        CoinIcon(symbol: o.baseAsset, size: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("\(o.baseAsset)USDT").font(Theme.f(18, .semibold))
                                Chip(text: "永续", fg: Theme.text3)
                            }
                            HStack(spacing: 6) {
                                Chip(text: o.side.label, fg: .white, bg: o.side == .long ? Theme.green : Theme.red)
                                Chip(text: o.marginMode.label, fg: Theme.brand, bg: Theme.yellowBg)
                                Chip(text: "\(o.leverage)x", fg: Theme.brand, bg: Theme.yellowBg)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Fmt.price(filled.entryPrice)).font(Theme.f(18, .semibold))
                            Text("开仓均价").font(Theme.tiny).foregroundStyle(Theme.text3)
                        }
                    }.padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.r8))

                    VStack(spacing: 0) {
                        line("数量", String(format: "%.4f %@", filled.quantity, o.baseAsset))
                        line("保证金", Fmt.usdt(o.notionalUSDT))
                        line("名义价值", Fmt.usdt(o.notionalUSDT * Double(o.leverage)))
                        if let tp = o.takeProfit { line("止盈", Fmt.price(tp.resolved(entry: filled.entryPrice, side: o.side, isTakeProfit: true)), color: Theme.green) }
                        if let sl = o.stopLoss { line("止损", Fmt.price(sl.resolved(entry: filled.entryPrice, side: o.side, isTakeProfit: false)), color: Theme.red) }
                        line("预估强平价", Fmt.price(filled.liquidationPrice), color: Theme.brand)
                        line("订单类型", "市价")
                        line("成交时间", filled.filledAt.formatted(date: .numeric, time: .standard))
                        line("订单号", filled.orderId, last: true)
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.r8))
                }.padding(16)
            }
            VStack(spacing: 0) {
                Rectangle().fill(Theme.line).frame(height: 1)
                Button("完成") { state.reset() }.buttonStyle(BinanceButton())
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            }
        }
        .onAppear { withAnimation(.spring(duration: 0.6, bounce: 0.4)) { appear = true } }
    }

    private func line(_ k: String, _ v: String, color: Color = Theme.text, last: Bool = false) -> some View {
        HStack {
            Text(k).font(Theme.body).foregroundStyle(Theme.text3)
            Spacer()
            Text(v).font(Theme.bodyM).foregroundStyle(color)
        }
        .padding(.horizontal, 16).frame(height: 44)
        .bnDivider(leading: last ? 1000 : 16)
    }
}
