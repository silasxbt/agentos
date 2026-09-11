import SwiftUI

struct ListeningView: View {
    @EnvironmentObject var state: AppState
    @State private var phase = 0.0

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: state.stage == .parsing ? "解析中" : "语音下单") {
                Button("取消") { state.cancelListening() }.foregroundStyle(Theme.text3)
            } trailing: { EmptyView() }

            Spacer()

            if state.stage == .parsing {
                ProgressView().controlSize(.large).tint(Theme.brand)
                Text("Agent 正在理解指令…").font(Theme.h2).padding(.top, 16)
            } else {
                Waveform(level: state.speech.level, phase: phase)
                    .frame(height: 100).padding(.horizontal, 32)
                HStack(spacing: 6) {
                    Circle().fill(Theme.red).frame(width: 6, height: 6)
                    Text(state.speech.isListening ? "正在聆听" : "准备中").font(Theme.caption).foregroundStyle(Theme.text3)
                }.padding(.top, 16)
            }

            Text(state.speech.transcript.isEmpty ? "说出:方向 · 币种 · 杠杆 · 全仓/逐仓 · 金额 · 止盈止损" : state.speech.transcript)
                .font(state.speech.transcript.isEmpty ? Theme.body : Theme.f(20, .medium))
                .foregroundStyle(state.speech.transcript.isEmpty ? Theme.text3 : Theme.text)
                .multilineTextAlignment(.center).padding(.horizontal, 32).padding(.top, 24)
                .frame(minHeight: 90)

            if let err = state.speech.errorMessage {
                Text(err).font(Theme.caption).foregroundStyle(Theme.red).padding(.horizontal)
            }

            Spacer()

            if state.stage == .listening {
                Button { state.stopListening() } label: {
                    ZStack {
                        Circle().stroke(Theme.line2, lineWidth: 1).frame(width: 80, height: 80)
                        Circle().fill(Theme.yellow).frame(width: 64, height: 64)
                        Image(systemName: "stop.fill").font(.system(size: 24)).foregroundStyle(Theme.onYellow)
                    }
                }.buttonStyle(.plain)
                Text("说完后停顿,或点击结束").font(Theme.caption).foregroundStyle(Theme.text3).padding(.top, 12)
            }
        }
        .padding(.bottom, 32)
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) { phase = .pi * 2 }
        }
    }
}

struct Waveform: View {
    var level: Float
    var phase: Double
    private let bars = 32

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<bars, id: \.self) { i in
                let x = Double(i) / Double(bars)
                let env = sin(x * .pi)
                let wave = (sin(x * 6 + phase * 3) + 1) / 2
                let amp = CGFloat(0.1 + env * wave * (0.25 + Double(level) * 0.75))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.brand.opacity(0.45 + Double(env) * 0.55))
                    .frame(width: 4, height: max(4, 100 * amp))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
