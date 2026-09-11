import ActivityKit
import WidgetKit
import SwiftUI

@main
struct BinanceVoiceWidgetBundle: WidgetBundle {
    var body: some Widget { TradeLiveActivity() }
}

struct TradeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TradeActivityAttributes.self) { ctx in
            LockScreenCard(state: ctx.state)
                .activityBackgroundTint(Theme.bg)
                .activitySystemActionForegroundColor(Theme.yellow)
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        SideBadge(side: s.order.side)
                        Text(s.order.baseAsset).font(.title3.bold())
                    }.padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(s.order.leverage)x · \(s.order.marginMode == .cross ? "全仓" : "逐仓")")
                        .font(.subheadline.bold()).foregroundStyle(Theme.yellow).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    ConfigLine(state: s)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActionRow(state: s).padding(.top, 4)
                }
            } compactLeading: {
                HStack(spacing: 4) { SideBadge(side: s.order.side, small: true); Text(s.order.baseAsset).font(.caption.bold()) }
            } compactTrailing: {
                PhaseTag(state: s)
            } minimal: {
                Image(systemName: "hexagon.fill").foregroundStyle(Theme.yellow)
            }
            .keylineTint(Theme.yellow)
            .widgetURL(DeepLink.edit)
        }
    }
}

// MARK: - pieces

struct SideBadge: View {
    let side: TradeSide
    var small = false
    var body: some View {
        Text(side.short).font(small ? .caption2.bold() : .caption.bold()).foregroundStyle(.black)
            .frame(width: small ? 16 : 22, height: small ? 16 : 22)
            .background(side == .long ? Theme.green : Theme.red, in: RoundedRectangle(cornerRadius: 5))
    }
}

struct PhaseTag: View {
    let state: TradeActivityAttributes.ContentState
    var body: some View {
        switch state.phase {
        case .pending: Text("\(state.order.leverage)x").font(.caption.bold()).foregroundStyle(Theme.yellow)
        case .submitting: ProgressView().tint(Theme.yellow).controlSize(.mini)
        case .filled: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.red)
        case .cancelled: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }
}

struct ConfigLine: View {
    let state: TradeActivityAttributes.ContentState
    var body: some View {
        let o = state.order
        VStack(spacing: 3) {
            HStack(spacing: 10) {
                Text("保证金 \(Fmt.usdt(o.notionalUSDT))")
                if let tp = o.takeProfit { Text("止盈 \(tp.display)").foregroundStyle(Theme.green) }
                if let sl = o.stopLoss { Text("止损 \(sl.display)").foregroundStyle(Theme.red) }
            }.font(.caption).lineLimit(1).minimumScaleFactor(0.7)
            if !o.missingFields.isEmpty {
                Text("缺少:\(o.missingFields.joined(separator: "、")),请点修改").font(.caption2).foregroundStyle(Theme.red)
            }
        }
    }
}

struct ActionRow: View {
    let state: TradeActivityAttributes.ContentState
    var body: some View {
        switch state.phase {
        case .pending:
            HStack(spacing: 8) {
                Button(intent: CancelFromIslandIntent()) { Text("取消").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).tint(.gray)
                Link(destination: DeepLink.edit) {
                    Text("修改").frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 8))
                }
                if state.order.missingFields.isEmpty {
                    if state.requireBiometrics {
                        Link(destination: DeepLink.submit) {
                            Label("下单", systemImage: "faceid").frame(maxWidth: .infinity).padding(.vertical, 7)
                                .foregroundStyle(.black).bold()
                                .background(Theme.yellow, in: RoundedRectangle(cornerRadius: 8))
                        }
                    } else {
                        Button(intent: SubmitFromIslandIntent()) { Text("下单").bold().frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).tint(Theme.yellow).foregroundStyle(.black)
                    }
                }
            }.font(.subheadline)
        case .submitting:
            HStack { ProgressView().tint(Theme.yellow); Text("正在提交到 Binance…") }.font(.subheadline)
        case .filled:
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                Text("已成交 @ \(Fmt.price(state.entryPrice ?? 0))  #\(state.orderId ?? "")").font(.subheadline.bold())
            }
        case .failed:
            Label(state.message ?? "下单失败", systemImage: "xmark.circle.fill").foregroundStyle(Theme.red).font(.subheadline)
        case .cancelled:
            Text("已取消").foregroundStyle(.secondary).font(.subheadline)
        }
    }
}

struct LockScreenCard: View {
    let state: TradeActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "hexagon.fill").foregroundStyle(Theme.yellow)
                Text("Binance Voice").font(.caption.bold()).foregroundStyle(Theme.text2)
                Spacer()
                Text("置信度 \(Int(state.confidence * 100))%").font(.caption2).foregroundStyle(Theme.text2)
            }
            HStack(spacing: 8) {
                SideBadge(side: state.order.side)
                Text("\(state.order.baseAsset)USDT").font(.title3.bold())
                Text("\(state.order.leverage)x · \(state.order.marginMode == .cross ? "全仓" : "逐仓")").foregroundStyle(Theme.yellow).bold()
                Spacer()
            }
            ConfigLine(state: state)
            ActionRow(state: state)
        }
        .padding(14).foregroundStyle(.white)
    }
}
