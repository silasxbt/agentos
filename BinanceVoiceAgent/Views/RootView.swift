import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch state.stage {
            case .idle: HomeView()
            case .listening, .parsing: ListeningView()
            case .confirm, .authenticating, .submitting: ConfirmView()
            case .success(let f): ResultView(filled: f)
            case .failed(let msg): FailedView(message: msg)
            }
        }
        .foregroundStyle(Theme.text)
        .tint(Theme.yellow)
        .animation(.spring(duration: 0.35), value: state.stage)
        .onAppear(perform: runDemoArgsIfAny)
    }

    /// 仅供自动化演示:xcrun simctl launch ... -demoTranscript "做多比特币…" [-autoSubmit | -island]
    private func runDemoArgsIfAny() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoTranscript"), i + 1 < args.count else { return }
        if args.contains("-island") { Task { await IslandFlow.shared.start(transcript: args[i + 1]) }; return }
        state.handleTranscript(args[i + 1])
        if args.contains("-autoSubmit") {
            Task { try? await Task.sleep(for: .seconds(1.5)); state.confirmAndSubmit() }
        }
        #endif
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    hero
                    manualInput
                    examples
                    if !state.orders.history.isEmpty { recent }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .sheet(isPresented: $state.showSettings) { SettingsView() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            BinanceLogo(size: 22)
            Text("Binance").font(Theme.f(18, .bold)).foregroundStyle(Theme.text)
            Text("Voice").font(Theme.f(18, .bold)).foregroundStyle(Theme.brand)
            Spacer()
            Chip(text: "USDⓈ-M 合约", fg: Theme.text2)
            Button { state.showSettings = true } label: {
                Image(systemName: "gearshape").font(Theme.f(18, .medium)).foregroundStyle(Theme.text)
            }.padding(.leading, 8)
        }
        .padding(.horizontal, 16).frame(height: 44)
    }

    /// 顶部主操作:Binance 风格“大数值 + 主按钮”的黄卡
    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 语音下单").font(Theme.f(22, .semibold)).foregroundStyle(Theme.text)
                    Text("一句话开仓:方向 · 币种 · 杠杆 · 全仓/逐仓 · 保证金 · 止盈止损")
                        .font(Theme.caption).foregroundStyle(Theme.text3)
                }
                Spacer()
                Image(systemName: "waveform").font(Theme.f(28, .medium)).foregroundStyle(Theme.brand)
            }
            .padding(16)

            Rectangle().fill(Theme.line).frame(height: 1)

            VStack(spacing: 12) {
                Button { state.triggerListening() } label: {
                    HStack(spacing: 8) { Image(systemName: "mic.fill"); Text("开始听写") }
                }.buttonStyle(BinanceButton())

                HStack(spacing: 6) {
                    Image(systemName: "button.vertical.left.press.fill").foregroundStyle(Theme.text3)
                    Text("或按侧边 Action Button,在任意 App 直接说指令").font(Theme.caption).foregroundStyle(Theme.text3)
                    Spacer()
                    Button("设置") { state.showSettings = true }.font(Theme.captionM).foregroundStyle(Theme.brand)
                }
            }
            .padding(16)
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.r8))
    }

    private var manualInput: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.text3)
            TextField("", text: $state.manualText, prompt: Text("输入指令,例如:做多 BTC 10倍 全仓 200U").foregroundStyle(Theme.text4))
                .font(Theme.body).foregroundStyle(Theme.text)
                .textFieldStyle(.plain).submitLabel(.send)
                .onSubmit { state.submitManual() }
            if !state.manualText.isEmpty {
                Button { state.submitManual() } label: {
                    Text("解析").font(Theme.captionM).foregroundStyle(Theme.onYellow)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.yellow, in: RoundedRectangle(cornerRadius: Theme.r4))
                }
            }
        }
        .padding(.horizontal, 12).frame(height: 44)
        .background(Theme.card2, in: RoundedRectangle(cornerRadius: Theme.r4))
    }

    private let samples: [(String, String, TradeSide)] = [
        ("BTC", "做多比特币 十倍 全仓 200U 止盈7万 止损6.5万", .long),
        ("ETH", "做空以太坊 20倍 逐仓 500U 止盈5% 止损3%", .short),
        ("SOL", "买入 SOL 5倍 全仓 1000 USDT", .long),
    ]

    private var examples: some View {
        section("试试这样说") {
            ForEach(Array(samples.enumerated()), id: \.offset) { i, s in
                Button { state.handleTranscript(s.1) } label: {
                    HStack(spacing: 12) {
                        CoinIcon(symbol: s.0)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("\(s.0)USDT").font(Theme.bodyS).foregroundStyle(Theme.text)
                                Chip(text: "永续", fg: Theme.text3)
                            }
                            Text(s.1).font(Theme.caption).foregroundStyle(Theme.text3).lineLimit(1)
                        }
                        Spacer()
                        Text(s.2 == .long ? "做多" : "做空").font(Theme.captionM)
                            .foregroundStyle(s.2 == .long ? Theme.green : Theme.red)
                        Image(systemName: "chevron.right").font(Theme.tiny).foregroundStyle(Theme.text4)
                    }
                    .padding(.horizontal, 16).frame(height: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .bnDivider(leading: i == samples.count - 1 ? 1000 : 16)
            }
        }
    }

    private var recent: some View {
        section("最近成交") {
            let items = Array(state.orders.history.prefix(5))
            ForEach(Array(items.enumerated()), id: \.element.id) { i, f in
                HStack(spacing: 12) {
                    CoinIcon(symbol: f.order.baseAsset)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("\(f.order.baseAsset)USDT").font(Theme.bodyS).foregroundStyle(Theme.text)
                            Chip(text: "\(f.order.marginMode.label) \(f.order.leverage)x", fg: Theme.brand, bg: Theme.yellowBg)
                        }
                        Text(f.filledAt.formatted(date: .numeric, time: .shortened)).font(Theme.caption).foregroundStyle(Theme.text3)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(Fmt.price(f.entryPrice)).font(Theme.num).foregroundStyle(Theme.text)
                        Text(f.order.side == .long ? "开多" : "开空").font(Theme.caption)
                            .foregroundStyle(f.order.side == .long ? Theme.green : Theme.red)
                    }
                }
                .padding(.horizontal, 16).frame(height: 60)
                .bnDivider(leading: i == items.count - 1 ? 1000 : 16)
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(Theme.h2).foregroundStyle(Theme.text).padding(.horizontal, 16).padding(.vertical, 12)
            content()
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.r8))
    }
}

typealias BinanceLogo = BrandLogo

/// 币种圆形图标(首字母,币安列表样式)
struct CoinIcon: View {
    let symbol: String
    var size: CGFloat = 32
    private var color: Color {
        switch symbol.uppercased() {
        case "BTC": return Color(hex: 0xF7931A)
        case "ETH": return Color(hex: 0x627EEA)
        case "SOL": return Color(hex: 0x9945FF)
        case "BNB": return Theme.brand
        case "DOGE": return Color(hex: 0xC2A633)
        case "XRP": return Color(hex: 0x23292F)
        default: return Theme.card2
        }
    }
    var body: some View {
        Text(String(symbol.prefix(1))).font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(.white)
            .frame(width: size, height: size).background(color, in: Circle())
    }
}

// MARK: - Failed

struct FailedView: View {
    @EnvironmentObject var state: AppState
    let message: String
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "xmark.circle.fill").font(.system(size: 64)).foregroundStyle(Theme.red)
            Text("下单失败").font(Theme.title)
            Text(message).font(Theme.body).foregroundStyle(Theme.text3).multilineTextAlignment(.center)
            Spacer()
            Button("返回") { state.reset() }.buttonStyle(BinanceButton())
        }.padding(16)
    }
}

/// 兼容旧调用
typealias PrimaryButton = BinanceButton

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    group("安全") {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("下单前 \(BiometricService.kindName) 确认").font(Theme.bodyM).foregroundStyle(Theme.text)
                                Text("关闭时仅需手机已解锁,灵动岛「下单」直接后台成交;开启后会跳回 App 验证。")
                                    .font(Theme.caption).foregroundStyle(Theme.text3)
                            }
                            Spacer()
                            Toggle("", isOn: $state.requireBiometrics).labelsHidden().tint(Theme.green)
                        }.padding(16)
                    }
                    group("两种触发方式(均不打开 App)") {
                        VStack(alignment: .leading, spacing: 14) {
                            path("全局语音", "Apple 听写 · 灵动岛确认", Theme.brand,
                                 "快捷指令:「听写文本」(中文)→「Binance Voice → 全局语音下单」,听写结果接到「交易指令」。任意界面按侧键 → 灵动岛 取消 / 编辑 / 下单。")
                            path("增强语音", "增强识别 · 一键录音", Theme.yellow,
                                 "设置 → 操作按钮 → 快捷指令 → 「Binance Voice → 增强语音」。按下直接录音(App 保持后台),点「停止」后识别,灵动岛显示结果:取消 / 编辑 / 下单。下单 → 立刻通知成功或失败;编辑 → 打开 App,字段已回填。")
                        }.padding(16)
                    }
                    group("关于") {
                        VStack(spacing: 0) {
                            kv("下单通道", "模拟 USDⓈ-M 合约")
                            kv("语音识别", "App 内置增强识别")
                            kv("版本", "1.0", last: true)
                        }
                    }
                }.padding(16)
            }
            .background(Theme.bg)
            .toolbarBackground(Theme.bg, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() }.font(Theme.bodyM).foregroundStyle(Theme.brand) }
        }
        .foregroundStyle(Theme.text)
    }
    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.caption).foregroundStyle(Theme.text3).padding(.horizontal, 4)
            content().frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.r8))
        }
    }
    private func path(_ name: String, _ tag: String, _ color: Color, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(name).font(Theme.bodyM).foregroundStyle(Theme.text)
                Chip(text: tag, fg: color, bg: color.opacity(0.12))
            }
            Text(desc).font(Theme.caption).foregroundStyle(Theme.text3)
        }
    }
    private func step(_ n: Int, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(Theme.tiny).frame(width: 18, height: 18).background(Theme.yellow, in: Circle()).foregroundStyle(Theme.onYellow)
            Text(t).font(Theme.body).foregroundStyle(Theme.text)
        }
    }
    private func kv(_ k: String, _ v: String, last: Bool = false) -> some View {
        HStack { Text(k).font(Theme.body).foregroundStyle(Theme.text3); Spacer(); Text(v).font(Theme.body).foregroundStyle(Theme.text) }
            .padding(.horizontal, 16).frame(height: 48)
            .bnDivider(leading: last ? 1000 : 16)
    }
}
