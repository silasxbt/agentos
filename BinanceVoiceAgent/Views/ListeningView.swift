import SwiftUI

struct ListeningView: View {
    @EnvironmentObject var state: AppState
    @State private var phase = 0.0

    var body: some View {
        VStack(spacing: 28) {
            HStack {
                Button("取消") { state.cancelListening() }.foregroundStyle(Theme.text2)
                Spacer()
            }.padding(.horizontal, 20)

            Spacer()

            if state.stage == .parsing {
                ProgressView().controlSize(.large).tint(Theme.yellow)
                Text("Agent 正在理解指令…").font(.headline)
            } else {
                Waveform(level: state.speech.level, phase: phase)
                    .frame(height: 120).padding(.horizontal, 30)
                Text(state.speech.isListening ? "正在听…" : "准备中").font(.headline).foregroundStyle(Theme.text2)
            }

            Text(state.speech.transcript.isEmpty ? "说出:方向 · 币种 · 杠杆 · 全仓/逐仓 · 金额 · 止盈止损" : state.speech.transcript)
                .font(state.speech.transcript.isEmpty ? .subheadline : .title3.weight(.medium))
                .foregroundStyle(state.speech.transcript.isEmpty ? Theme.text2 : .primary)
                .multilineTextAlignment(.center).padding(.horizontal, 28)
                .frame(minHeight: 80)

            if let err = state.speech.errorMessage {
                Text(err).font(.caption).foregroundStyle(Theme.red).padding(.horizontal)
            }

            Spacer()

            if state.stage == .listening {
                Button { state.stopListening() } label: {
                    ZStack {
                        Circle().fill(Theme.yellow).frame(width: 84, height: 84)
                        Image(systemName: "stop.fill").font(.title).foregroundStyle(.black)
                    }
                }.buttonStyle(.plain)
                Text("说完后停顿或点击结束").font(.caption).foregroundStyle(Theme.text2)
            }
        }
        .padding(.bottom, 30)
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) { phase = .pi * 2 }
        }
    }
}

struct Waveform: View {
    var level: Float
    var phase: Double
    private let bars = 28

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(0..<bars, id: \.self) { i in
                let x = Double(i) / Double(bars)
                let env = sin(x * .pi)
                let wave = (sin(x * 6 + phase * 3) + 1) / 2
                let amp = CGFloat(0.12 + env * wave * (0.25 + Double(level) * 0.75))
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.yellow.opacity(0.55 + Double(env) * 0.45))
                    .frame(width: 6, height: max(6, 120 * amp))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
