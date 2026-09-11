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
        .animation(.spring(duration: 0.35), value: state.stage)
        .onAppear(perform: runDemoArgsIfAny)
    }

    /// 仅供自动化演示:xcrun simctl launch ... -demoTranscript "做多比特币…" [-autoSubmit]
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
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 20) {
                    actionButtonHint
                    micButton
                    manualInput
                    examples
                    if !state.orders.history.isEmpty { recent }
                }
                .padding(20)
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "hexagon.fill").foregroundStyle(Theme.yellow).font(.title2)
            Text("Binance").font(.title2.bold())
            Text("Voice Agent").font(.title2).foregroundStyle(Theme.text2)
            Spacer()
            Text("Futures").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.card2, in: Capsule()).foregroundStyle(Theme.yellow)
            Button { state.showSettings = true } label: { Image(systemName: "gearshape.fill").foregroundStyle(Theme.text2) }
                .padding(.leading, 6)
        }
        .sheet(isPresented: $state.showSettings) { SettingsView() }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
    }

    private var actionButtonHint: some View {
        HStack(spacing: 12) {
            Image(systemName: "button.vertical.left.press.fill").font(.title).foregroundStyle(Theme.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("按下侧边 Action Button 即可开口下单").font(.subheadline.bold())
                Text("设置 → 操作按钮 → 快捷指令 → 语音下单").font(.caption).foregroundStyle(Theme.text2)
            }
            Spacer()
        }
        .padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var micButton: some View {
        Button { state.triggerListening() } label: {
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.yellow.opacity(0.15)).frame(width: 150, height: 150)
                    Circle().fill(Theme.yellow).frame(width: 110, height: 110)
                    Image(systemName: "mic.fill").font(.system(size: 44)).foregroundStyle(.black)
                }
                Text("点击开始听写").font(.headline)
            }
        }
        .buttonStyle(.plain).padding(.vertical, 10)
    }

    private var manualInput: some View {
        HStack {
            TextField("或直接输入指令…", text: $state.manualText)
                .textFieldStyle(.plain).submitLabel(.send)
                .onSubmit { state.submitManual() }
            Button { state.submitManual() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }.disabled(state.manualText.isEmpty)
        }
        .padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private let samples = [
        "做多比特币 十倍 全仓 200U 止盈7万 止损6.5万",
        "做空以太坊 20倍 逐仓 500U 止盈5% 止损3%",
        "买入 SOL 5倍 全仓 1000 USDT",
    ]

    private var examples: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("试试这样说").font(.caption).foregroundStyle(Theme.text2)
            ForEach(samples, id: \.self) { s in
                Button { state.handleTranscript(s) } label: {
                    HStack {
                        Image(systemName: "quote.opening").font(.caption2).foregroundStyle(Theme.yellow)
                        Text(s).font(.subheadline).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.text2)
                    }
                    .padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近成交").font(.caption).foregroundStyle(Theme.text2)
            ForEach(state.orders.history.prefix(5)) { f in
                HStack {
                    Text(f.order.side.short).font(.caption.bold()).frame(width: 24, height: 24)
                        .background(f.order.side == .long ? Theme.green : Theme.red, in: RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading) {
                        Text("\(f.order.baseAsset)USDT \(f.order.leverage)x").font(.subheadline.bold())
                        Text(f.filledAt.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(Theme.text2)
                    }
                    Spacer()
                    Text(Fmt.price(f.entryPrice)).font(.subheadline.monospacedDigit())
                }
                .padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Failed

struct FailedView: View {
    @EnvironmentObject var state: AppState
    let message: String
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "xmark.octagon.fill").font(.system(size: 72)).foregroundStyle(Theme.red)
            Text("下单失败").font(.title.bold())
            Text(message).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            Spacer()
            Button("返回") { state.reset() }.buttonStyle(PrimaryButton())
        }.padding(24)
    }
}

struct PrimaryButton: ButtonStyle {
    var color: Color = Theme.yellow
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline).foregroundStyle(.black)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("安全") {
                    Toggle(isOn: $state.requireBiometrics) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("下单前 \(BiometricService.kindName) 确认")
                            Text("关闭时仅需手机已解锁。开启后灵动岛「下单」会跳回 App 验证。").font(.caption).foregroundStyle(Theme.text2)
                        }
                    }.tint(Theme.yellow)
                }
                Section("Action Button 全局触发(不打开 App)") {
                    step(1, "打开「快捷指令」App,新建快捷指令")
                    step(2, "添加动作「听写文本」(语言:中文)")
                    step(3, "添加动作「Binance Voice → 语音下单(灵动岛)」,把听写文本接到「交易指令」")
                    step(4, "设置 → 操作按钮 → 快捷指令 → 选择它")
                    Text("之后在 Coinglass / TradingView 任意界面按侧键:说指令 → 灵动岛显示配置 → 点「下单」→ 通知成交。")
                        .font(.caption).foregroundStyle(Theme.text2)
                }
                Section("关于") {
                    LabeledContent("下单通道", value: "模拟 USDⓈ-M 合约")
                    LabeledContent("版本", value: "1.0")
                }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() } }
        }
    }
    private func step(_ n: Int, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.caption.bold()).frame(width: 20, height: 20).background(Theme.yellow, in: Circle()).foregroundStyle(.black)
            Text(t).font(.subheadline)
        }
    }
}
