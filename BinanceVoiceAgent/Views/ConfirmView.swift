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
    private var busy: Bool { state.stage == .authenticating || state.stage == .submitting }
    private var mark: Double? { OrderService.markPrice(order.wrappedValue.symbol) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("重新说") { state.startListening() }.disabled(busy)
                Spacer()
                Text("确认订单").font(.headline)
                Spacer()
                Button("取消") { state.reset() }.foregroundStyle(Theme.text2).disabled(busy)
            }.padding(.horizontal, 20).padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 14) {
                    transcriptCard
                    agentCard
                    fieldsCard
                    tpslCard
                    if !order.wrappedValue.missingFields.isEmpty {
                        Label("请补全:\(order.wrappedValue.missingFields.joined(separator: "、"))", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(Theme.red)
                    }
                }.padding(20)
            }

            submitBar
        }
        .onAppear(perform: syncFromDraft)
        .disabled(busy)
    }

    // MARK: cards

    private var transcriptCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform").foregroundStyle(Theme.yellow)
            Text("“\(order.wrappedValue.rawTranscript)”").font(.subheadline).italic()
            Spacer()
        }.padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var agentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(Theme.yellow)
                Text("Agent 理解").font(.subheadline.bold())
                Spacer()
                Text("置信度 \(Int(state.confidence * 100))%").font(.caption)
                    .foregroundStyle(state.confidence > 0.7 ? Theme.green : Theme.yellow)
            }
            Text(order.wrappedValue.summary).font(.body.weight(.medium))
            ForEach(state.agentNotes, id: \.self) { n in
                Label(n, systemImage: "info.circle").font(.caption).foregroundStyle(Theme.text2)
            }
            if let mark {
                Text("标记价 \(Fmt.price(mark))  ·  预计仓位 \(String(format: "%.4f", order.wrappedValue.notionalUSDT * Double(order.wrappedValue.leverage) / mark)) \(order.wrappedValue.baseAsset)")
                    .font(.caption).foregroundStyle(Theme.text2)
            }
        }.padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var fieldsCard: some View {
        VStack(spacing: 14) {
            row("币种") {
                TextField("BTC", text: Binding(
                    get: { order.wrappedValue.baseAsset },
                    set: { order.wrappedValue.symbol = $0.uppercased().isEmpty ? "" : $0.uppercased().replacingOccurrences(of: "USDT", with: "") + "USDT" }))
                    .multilineTextAlignment(.trailing).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(.body.bold())
                Text("USDT 永续").font(.caption).foregroundStyle(Theme.text2)
            }
            Picker("方向", selection: order.side) {
                ForEach(TradeSide.allCases) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            Picker("仓位模式", selection: order.marginMode) {
                ForEach(MarginMode.allCases) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            VStack(spacing: 6) {
                HStack {
                    Text("杠杆").foregroundStyle(Theme.text2)
                    Spacer()
                    Text("\(order.wrappedValue.leverage)x").font(.title3.bold().monospacedDigit()).foregroundStyle(Theme.yellow)
                }
                Slider(value: Binding(get: { Double(order.wrappedValue.leverage) }, set: { order.wrappedValue.leverage = Int($0) }), in: 1...125, step: 1)
                HStack {
                    ForEach([1, 5, 10, 20, 50, 100], id: \.self) { l in
                        Button("\(l)x") { order.wrappedValue.leverage = l }
                            .font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 6)
                            .background(order.wrappedValue.leverage == l ? Theme.yellow : Theme.card2, in: Capsule())
                            .foregroundStyle(order.wrappedValue.leverage == l ? .black : .primary)
                    }
                }
            }
            row("保证金") {
                TextField("100", text: $amountText).keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(.body.bold())
                    .onChange(of: amountText) { _, v in order.wrappedValue.notionalUSDT = Double(v) ?? 0 }
                Text("USDT").font(.caption).foregroundStyle(Theme.text2)
            }
        }.padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var tpslCard: some View {
        VStack(spacing: 12) {
            targetRow(title: "止盈 TP", on: $tpOn, text: $tpText, pct: $tpPct, color: Theme.green) { order.wrappedValue.takeProfit = $0 }
            Divider().overlay(Theme.card2)
            targetRow(title: "止损 SL", on: $slOn, text: $slText, pct: $slPct, color: Theme.red) { order.wrappedValue.stopLoss = $0 }
        }.padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func targetRow(title: String, on: Binding<Bool>, text: Binding<String>, pct: Binding<Bool>, color: Color,
                           apply: @escaping (PriceTarget?) -> Void) -> some View {
        VStack(spacing: 8) {
            Toggle(isOn: on) { Text(title).foregroundStyle(color).bold() }.tint(color)
            if on.wrappedValue {
                HStack {
                    TextField(pct.wrappedValue ? "5" : "价格", text: text).keyboardType(.decimalPad).font(.body.bold())
                    Picker("", selection: pct) { Text("价格").tag(false); Text("%").tag(true) }
                        .pickerStyle(.segmented).frame(width: 120)
                }
                if let m = mark, let v = Double(text.wrappedValue) {
                    let t: PriceTarget = pct.wrappedValue ? .percent(v) : .price(v)
                    Text("触发价约 \(Fmt.price(t.resolved(entry: m, side: order.wrappedValue.side, isTakeProfit: title.hasPrefix("止盈"))))")
                        .font(.caption).foregroundStyle(Theme.text2).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .modifier(ApplyOnChange(on: on, text: text, pct: pct, apply: apply))
    }

    private var submitBar: some View {
        VStack(spacing: 10) {
            if busy {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.yellow)
                    Text(state.stage == .authenticating ? "等待 \(BiometricService.kindName) 确认…" : "正在提交到 Binance…")
                }.font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            } else {
                Button { state.confirmAndSubmit() } label: {
                    Label("提交 · \(BiometricService.kindName) 确认", systemImage: "faceid")
                }
                .buttonStyle(PrimaryButton(color: order.wrappedValue.side == .long ? Theme.green : Theme.red))
                .disabled(!order.wrappedValue.missingFields.isEmpty)
                .opacity(order.wrappedValue.missingFields.isEmpty ? 1 : 0.4)
            }
        }.padding(20).background(Theme.bg)
    }

    private func row<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        HStack { Text(title).foregroundStyle(Theme.text2); Spacer(); content() }
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
