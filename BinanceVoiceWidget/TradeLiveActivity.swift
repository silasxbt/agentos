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
                .activityBackgroundTint(Theme.card)
                .activitySystemActionForegroundColor(Theme.brand)
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if s.isPreOrder {
                        HStack(spacing: 6) { Image(systemName: "hexagon.fill").foregroundStyle(Theme.brand); Text("Binance Voice").font(Theme.captionM).foregroundStyle(Theme.text2) }.padding(.leading, 4)
                    } else {
                        HStack(spacing: 6) {
                            SideBadge(side: s.order.side)
                            Text(s.order.baseAsset).font(Theme.h2).foregroundStyle(Theme.text)
                        }.padding(.leading, 4)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if s.isPreOrder {
                        Chip(text: "Qwen ASR", fg: Theme.brand, bg: Theme.yellowBg).padding(.trailing, 4)
                    } else {
                        HStack(spacing: 4) {
                            Chip(text: s.order.marginMode == .cross ? "全仓" : "逐仓", fg: Theme.brand, bg: Theme.yellowBg)
                            Chip(text: "\(s.order.leverage)x", fg: Theme.brand, bg: Theme.yellowBg)
                        }.padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if !s.isPreOrder { ConfigLine(state: s) }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActionRow(state: s).padding(.top, 4)
                }
            } compactLeading: {
                if s.isPreOrder {
                    Image(systemName: s.phase == .listening ? "mic.fill" : "waveform").foregroundStyle(Theme.brand)
                } else {
                    HStack(spacing: 4) { SideBadge(side: s.order.side, small: true); Text(s.order.baseAsset).font(Theme.captionM).foregroundStyle(Theme.text) }
                }
            } compactTrailing: {
                PhaseTag(state: s)
            } minimal: {
                Image(systemName: "hexagon.fill").foregroundStyle(Theme.brand)
            }
            .keylineTint(Theme.brand)
            .widgetURL(DeepLink.edit)
        }
    }
}

// MARK: - pieces

struct SideBadge: View {
    let side: TradeSide
    var small = false
    var body: some View {
        Text(side.short).font(small ? Theme.tiny : Theme.captionM).foregroundStyle(.white)
            .frame(width: small ? 16 : 22, height: small ? 16 : 22)
            .background(side == .long ? Theme.green : Theme.red, in: RoundedRectangle(cornerRadius: Theme.r4))
    }
}

struct PhaseTag: View {
    let state: TradeActivityAttributes.ContentState
    var body: some View {
        switch state.phase {
        case .listening: Text("聆听中").font(Theme.captionM).foregroundStyle(Theme.brand)
        case .transcribing: ProgressView().tint(Theme.brand).controlSize(.mini)
        case .pending: Text("\(state.order.leverage)x").font(Theme.captionM).foregroundStyle(Theme.brand)
        case .submitting: ProgressView().tint(Theme.brand).controlSize(.mini)
        case .filled: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.red)
        case .cancelled: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }
}

struct ConfigLine: View {
    let state: TradeActivityAttributes.ContentState
    private func kv(_ k: String, _ v: String, _ c: Color) -> some View {
        HStack(spacing: 4) {
            Text(k).font(Theme.caption).foregroundStyle(Theme.text3)
            Text(v).font(Theme.captionM).foregroundStyle(c)
        }
    }
    var body: some View {
        let o = state.order
        VStack(spacing: 3) {
            HStack(spacing: 12) {
                kv("保证金", Fmt.usdt(o.notionalUSDT), Theme.text)
                if let tp = o.takeProfit { kv("止盈", tp.display, Theme.green) }
                if let sl = o.stopLoss { kv("止损", sl.display, Theme.red) }
                Spacer(minLength: 0)
            }.lineLimit(1).minimumScaleFactor(0.7)
            if !o.missingFields.isEmpty {
                Text("缺少:\(o.missingFields.joined(separator: "、")),请点编辑").font(Theme.tiny).foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ActionRow: View {
    let state: TradeActivityAttributes.ContentState
    var body: some View {
        switch state.phase {
        case .listening, .transcribing:
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    if state.phase == .listening {
                        Image(systemName: "mic.fill").foregroundStyle(Theme.red).symbolEffect(.pulse)
                        Text("正在聆听,说完自动停止…").font(Theme.body).foregroundStyle(Theme.text)
                    } else {
                        ProgressView().tint(Theme.brand).controlSize(.small)
                        Text("Qwen 转写中…").font(Theme.body).foregroundStyle(Theme.text2)
                    }
                    Spacer(minLength: 0)
                }
                Button(intent: CancelFromIslandIntent()) { islandLabel("取消", fg: Theme.text, bg: Theme.card2) }
                    .buttonStyle(.plain).frame(width: 72)
            }
        case .pending:
            HStack(spacing: 8) {
                Button(intent: CancelFromIslandIntent()) { islandLabel("取消", fg: Theme.text, bg: Theme.card2) }
                    .buttonStyle(.plain)
                Link(destination: DeepLink.edit) { islandLabel("编辑", fg: Theme.text, bg: Theme.card2) }
                if state.order.missingFields.isEmpty {
                    let submitFill = state.order.side == .long ? Theme.green : Theme.red
                    let submitText = state.order.side == .long ? "确定 · 做多" : "确定 · 做空"
                    if state.requireBiometrics {
                        Link(destination: DeepLink.submit) { islandLabel(submitText, icon: "faceid", fg: .white, bg: submitFill) }
                    } else {
                        Button(intent: SubmitFromIslandIntent()) { islandLabel(submitText, fg: .white, bg: submitFill) }
                            .buttonStyle(.plain)
                    }
                }
            }
        case .submitting:
            HStack(spacing: 8) { ProgressView().tint(Theme.brand).controlSize(.small); Text("正在提交到 Binance…").font(Theme.body).foregroundStyle(Theme.text2) }
        case .filled:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                Text("已成交").font(Theme.bodyS).foregroundStyle(Theme.text)
                Text("@ \(Fmt.price(state.entryPrice ?? 0))").font(Theme.bodyM).foregroundStyle(Theme.text)
                Spacer()
                Text("#\(state.orderId ?? "")").font(Theme.caption).foregroundStyle(Theme.text3)
            }
        case .failed:
            Label(state.message ?? "下单失败", systemImage: "xmark.circle.fill").foregroundStyle(Theme.red).font(Theme.body)
        case .cancelled:
            Text("已取消").foregroundStyle(Theme.text3).font(Theme.body)
        }
    }

    private func islandLabel(_ t: String, icon: String? = nil, fg: Color, bg: Color) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(Theme.caption) }
            Text(t).font(Theme.bodyS)
        }
        .foregroundStyle(fg).frame(maxWidth: .infinity).frame(height: 36)
        .background(bg, in: RoundedRectangle(cornerRadius: Theme.r8))
    }
}

struct LockScreenCard: View {
    let state: TradeActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hexagon.fill").foregroundStyle(Theme.brand)
                Text("Binance Voice").font(Theme.captionM).foregroundStyle(Theme.text2)
                Spacer()
                if state.isPreOrder {
                    Chip(text: "Qwen ASR", fg: Theme.brand, bg: Theme.yellowBg)
                } else {
                    Chip(text: "置信度 \(Int(state.confidence * 100))%", fg: state.confidence > 0.7 ? Theme.green : Theme.brand,
                         bg: state.confidence > 0.7 ? Theme.greenBg : Theme.yellowBg)
                }
            }
            if !state.isPreOrder {
                HStack(spacing: 8) {
                    SideBadge(side: state.order.side)
                    Text("\(state.order.baseAsset)USDT").font(Theme.f(18, .semibold)).foregroundStyle(Theme.text)
                    Chip(text: "永续", fg: Theme.text3)
                    Chip(text: state.order.marginMode == .cross ? "全仓" : "逐仓", fg: Theme.brand, bg: Theme.yellowBg)
                    Chip(text: "\(state.order.leverage)x", fg: Theme.brand, bg: Theme.yellowBg)
                    Spacer()
                }
                ConfigLine(state: state)
            }
            ActionRow(state: state).padding(.top, 2)
        }
        .padding(14).foregroundStyle(Theme.text)
    }
}
