import SwiftUI

struct ConfirmView: View {
    @EnvironmentObject var state: AppState
    @State private var tpOn = false
    @State private var slOn = false
    @State private var tpText = ""
    @State private var slText = ""
    @State private var tpPct = false
    @State private var slPct = false
    @State private var amountText = ""

    private var order: Binding<TradeOrder> {
        Binding(get: { state.draft ?? TradeOrder(symbol: "", side: .long, leverage: 5, marginMode: .cross, notionalUSDT: 100) },
                set: { state.draft = $0 })
    }
    private var o: TradeOrder { order.wrappedValue }
    private var busy: Bool { state.stage == .authenticating || state.stage == .submitting }
    private var mark: Double? { OrderService.markPrice(o.symbol) }
    private var sideColor: Color { o.side == .long ? Theme.green : Theme.red }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "确认订单") {
                Button { state.startListening() } label: {
                    HStack(spacing: 4) { Image(systemName: "mic"); Text("重新说") }
                }.foregroundStyle(Theme.text).disabled(busy)
            } trailing: {
                Button("取消") { state.reset() }.foregroundStyle(Theme.text3).disabled(busy)
            }

            ScrollView {
                VStack(spacing: 12) {
                    symbolHeader
                    agentPanel
                    orderPanel
                    tpslPanel
                    if !o.missingFields.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text("请补全:\(o.missingFields.joined(separator: "、"))")
                        }.font(Theme.caption).foregroundStyle(Theme.red).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(16)
            }

            submitBar
        }
        .onAppear(perform: syncFromDraft)
        .disabled(busy)
    }

    // MARK: 交易对头部(Binance 合约页顶部样式)

    private var symbolHeader: some View {
        HStack(spacing: 12) {
            CoinIcon(symbol: o.baseAsset.isEmpty ? "?" : o.baseAsset, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TextField("BTC", text: Binding(
                        get: { o.baseAsset },
                        set: { order.wrappedValue.symbol = $0.uppercased().isEmpty ? "" : $0.uppercased().replacingOccurrences(of: "USDT", with: "") + "USDT" }))
                        .font(Theme.f(18, .semibold)).foregroundStyle(Theme.text)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled().fixedSize()
                    Text("USDT").font(Theme.f(18, .semibold)).foregroundStyle(Theme.text).padding(.leading, -6)
                    Chip(text: "永续", fg: Theme.text3)
                }
                HStack(spacing: 6) {
                    Chip(text: o.marginMode.label, fg: Theme.brand, bg: Theme.yellowBg)
                    Chip(text: "\(o.leverage)x", fg: Theme.brand, bg: Theme.yellowBg)
                }
            }
            Spacer()
            if let mark {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.price(mark)).font(Theme.f(18, .semibold)).foregroundStyle(Theme.text)
                    Text("标记价格").font(Theme.tiny).foregroundStyle(Theme.text3)
                }
            }
        }
        .padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.r8))
    }

    // MARK: Agent 理解

    private var agentPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(Theme.brand)
                    Text("Agent 理解").font(Theme.bodyS).foregroundStyle(Theme.text)
                    Spacer()
                    Chip(text: "置信度 \(Int(state.confidence * 100))%",
                         fg: state.confidence > 0.7 ? Theme.green : Theme.brand,
                         bg: state.confidence > 0.7 ? Theme.greenBg : Theme.yellowBg)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.opening").font(Theme.tiny).foregroundStyle(Theme.text4).padding(.top, 3)
                    Text(o.rawTranscript).font(Theme.body).foregroundStyle(Theme.text2)
                }
                Text(o.orderedSummary).font(Theme.bodyM).foregroundStyle(Theme.text)
                ForEach(state.agentNotes, id: \.self) { n in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle").font(Theme.caption).padding(.top, 1)
                        Text(n).font(Theme.caption)
                    }.foregroundStyle(Theme.text3)
                }
            }
        }
    }

    // MARK: 下单面板(方向 / 模式 / 杠杆 / 保证金)

    private var orderPanel: some View {
        Panel {
            VStack(spacing: 12) {
                BinanceSegment(items: [(TradeSide.long, "买入 / 做多"), (.short, "卖出 / 做空")], selection: order.side,
                               activeColor: { $0 == .long ? Theme.green : Theme.red }, activeFg: { _ in .white }, height: 40)

                HStack(spacing: 8) {
                    BinanceSegment(items: [(MarginMode.cross, "全仓"), (.isolated, "逐仓")], selection: order.marginMode,
                                   activeColor: { _ in Theme.card2 }, activeFg: { _ in Theme.brand })
                    HStack(spacing: 4) {
                        Text("\(o.leverage)x").font(Theme.bodyS).foregroundStyle(Theme.brand)
                        Image(systemName: "chevron.down").font(Theme.tiny).foregroundStyle(Theme.text3)
                    }
                    .frame(width: 72, height: 36)
                    .background(Theme.card2, in: RoundedRectangle(cornerRadius: Theme.r4))
                }

                VStack(spacing: 8) {
                    HStack {
                        Text("杠杆").font(Theme.caption).foregroundStyle(Theme.text3)
                        Spacer()
                        Text("\(o.leverage)x").font(Theme.numL).foregroundStyle(Theme.text)
                    }
                    Slider(value: Binding(get: { Double(o.leverage) }, set: { order.wrappedValue.leverage = Int($0) }), in: 1...125, step: 1)
                        .tint(Theme.yellow)
                    HStack(spacing: 6) {
                        ForEach([1, 5, 10, 20, 50, 100], id: \.self) { l in
                            let on = o.leverage == l
                            Button("\(l)x") { order.wrappedValue.leverage = l }
                                .font(Theme.captionM).frame(maxWidth: .infinity).frame(height: 28)
                                .background(on ? Theme.yellowBg : Theme.card2, in: RoundedRectangle(cornerRadius: Theme.r4))
                                .overlay(RoundedRectangle(cornerRadius: Theme.r4).stroke(on ? Theme.brand : .clear, lineWidth: 1))
                                .foregroundStyle(on ? Theme.brand : Theme.text2)
                        }
                    }
                }

                BinanceField(label: "保证金", unit: "USDT") {
                    TextField("", text: $amountText, prompt: Text("0").foregroundStyle(Theme.text4))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .onChange(of: amountText) { _, v in order.wrappedValue.notionalUSDT = Double(v) ?? 0 }
                }

                if let mark {
                    VStack(spacing: 6) {
                        kv("名义价值", Fmt.usdt(o.notionalUSDT * Double(o.leverage)))
                        kv("预计数量", String(format: "%.4f %@", o.notionalUSDT * Double(o.leverage) / mark, o.baseAsset))
                        kv("下单类型", "市价")
                    }
                }
            }
        }
    }

    // MARK: 止盈止损

    private var tpslPanel: some View {
        Panel {
            VStack(spacing: 12) {
                HStack {
                    Text("止盈 / 止损").font(Theme.bodyS).foregroundStyle(Theme.text)
                    Spacer()
                    Text("市价触发").font(Theme.caption).foregroundStyle(Theme.text3)
                }
                targetRow(title: "止盈", on: $tpOn, text: $tpText, pct: $tpPct, color: Theme.green, isTP: true) { order.wrappedValue.takeProfit = $0 }
                targetRow(title: "止损", on: $slOn, text: $slText, pct: $slPct, color: Theme.red, isTP: false) { order.wrappedValue.stopLoss = $0 }
            }
        }
    }

    private func targetRow(title: String, on: Binding<Bool>, text: Binding<String>, pct: Binding<Bool>, color: Color, isTP: Bool,
                           apply: @escaping (PriceTarget?) -> Void) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button { on.wrappedValue.toggle() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: on.wrappedValue ? "checkmark.square.fill" : "square")
                            .foregroundStyle(on.wrappedValue ? Theme.brand : Theme.text3)
                        Text(title).font(Theme.body).foregroundStyle(Theme.text)
                    }
                }.buttonStyle(.plain)
                Spacer()
                if on.wrappedValue, let m = mark, let v = Double(text.wrappedValue) {
                    let t: PriceTarget = pct.wrappedValue ? .percent(v) : .price(v)
                    Text("触发 \(Fmt.price(t.resolved(entry: m, side: o.side, isTakeProfit: isTP)))")
                        .font(Theme.caption).foregroundStyle(color)
                }
            }
            if on.wrappedValue {
                HStack(spacing: 8) {
                    HStack {
                        TextField("", text: text, prompt: Text(pct.wrappedValue ? "0" : "价格").foregroundStyle(Theme.text4))
                            .keyboardType(.decimalPad).font(Theme.num).foregroundStyle(Theme.text)
                        Text(pct.wrappedValue ? "%" : "USDT").font(Theme.body).foregroundStyle(Theme.text3)
                    }
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(Theme.card2, in: RoundedRectangle(cornerRadius: Theme.r4))
                    BinanceSegment(items: [(false, "价格"), (true, "%")], selection: pct, activeFg: { _ in Theme.brand }, height: 40)
                        .frame(width: 120)
                }
            }
        }
        .modifier(ApplyOnChange(on: on, text: text, pct: pct, apply: apply))
    }

    // MARK: 底部提交(Binance 买/卖按钮:多为绿、空为红,白字)

    private var submitBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.line).frame(height: 1)
            Group {
                if busy {
                    HStack(spacing: 10) {
                        ProgressView().tint(Theme.brand)
                        Text(state.stage == .authenticating ? "等待 \(BiometricService.kindName) 确认…" : "正在提交到 Binance…")
                            .font(Theme.bodyM).foregroundStyle(Theme.text2)
                    }.frame(maxWidth: .infinity).frame(height: 48)
                    .background(Theme.card2, in: RoundedRectangle(cornerRadius: Theme.r8))
                } else {
                    Button { state.confirmAndSubmit() } label: {
                        HStack(spacing: 6) {
                            if state.requireBiometrics { Image(systemName: "faceid") }
                            Text(o.side == .long ? "买入 / 做多 \(o.baseAsset)" : "卖出 / 做空 \(o.baseAsset)")
                        }
                    }
                    .buttonStyle(BinanceButton(fill: sideColor, fg: .white))
                    .disabled(!o.missingFields.isEmpty)
                    .opacity(o.missingFields.isEmpty ? 1 : 0.4)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
        }
        .background(Theme.bg)
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack { Text(k).font(Theme.caption).foregroundStyle(Theme.text3); Spacer(); Text(v).font(Theme.captionM).foregroundStyle(Theme.text2) }
    }

    private func syncFromDraft() {
        guard let d = state.draft else { return }
        amountText = d.notionalUSDT > 0 ? Fmt.price(d.notionalUSDT).replacingOccurrences(of: ",", with: "") : ""
        if let tp = d.takeProfit { tpOn = true; if case .percent(let p) = tp { tpPct = true; tpText = "\(p)" } else if case .price(let p) = tp { tpText = "\(p)" } }
        if let sl = d.stopLoss { slOn = true; if case .percent(let p) = sl { slPct = true; slText = "\(p)" } else if case .price(let p) = sl { slText = "\(p)" } }
    }
}

/// 把 toggle/文本/百分比三个状态合成为 PriceTarget 写回草稿
private struct ApplyOnChange: ViewModifier {
    @Binding var on: Bool
    @Binding var text: String
    @Binding var pct: Bool
    let apply: (PriceTarget?) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: on) { _, _ in sync() }
            .onChange(of: text) { _, _ in sync() }
            .onChange(of: pct) { _, _ in sync() }
    }
    private func sync() {
        guard on, let v = Double(text) else { apply(nil); return }
        apply(pct ? .percent(v) : .price(v))
    }
}
