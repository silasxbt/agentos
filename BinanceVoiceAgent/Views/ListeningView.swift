import SwiftUI

struct ListeningView: View {
    @EnvironmentObject var state: AppState
    /// SpeechService 是嵌套的 ObservableObject,必须单独观察,否则录音/转写状态变化不会刷新本视图
    @ObservedObject private var speech = AppState.shared.speech

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: state.stage == .parsing ? "解析中" : "语音下单") {
                Button("取消") { state.cancelListening() }.foregroundStyle(Theme.text3)
            } trailing: { EmptyView() }

            Spacer()

            if state.stage == .parsing {
                ProgressView().controlSize(.large).tint(Theme.brand)
                Text("Agent 正在理解指令…").font(Theme.h2).padding(.top, 16)
            } else if speech.isTranscribing {
                ProgressView().controlSize(.large).tint(Theme.brand)
                Text("Qwen 语音转写中…").font(Theme.h2).padding(.top, 16)
                Text("qwen-audio-3.0-asr-flash-filetrans").font(Theme.tiny).foregroundStyle(Theme.text3).padding(.top, 4)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                    Waveform(level: speech.level, phase: tl.date.timeIntervalSinceReferenceDate)
                }.frame(height: 100).padding(.horizontal, 32)
                HStack(spacing: 6) {
                    Circle().fill(Theme.red).frame(width: 6, height: 6)
                    Text(speech.isListening ? "正在聆听" : "准备中").font(Theme.caption).foregroundStyle(Theme.text3)
                }.padding(.top, 16)
            }

            Text(speech.transcript.isEmpty ? "说出:方向 · 币种 · 杠杆 · 全仓/逐仓 · 金额 · 止盈止损" : speech.transcript)
                .font(speech.transcript.isEmpty ? Theme.body : Theme.f(20, .medium))
                .foregroundStyle(speech.transcript.isEmpty ? Theme.text3 : Theme.text)
                .multilineTextAlignment(.center).padding(.horizontal, 32).padding(.top, 24)
                .frame(minHeight: 90)

            if let err = speech.errorMessage {
                Text(err).font(Theme.caption).foregroundStyle(Theme.red).padding(.horizontal).multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button("重试") { state.startListening() }.buttonStyle(SecondaryButton(height: 40))
                    Button("手动输入") { state.cancelListening() }.buttonStyle(SecondaryButton(height: 40))
                }.padding(.horizontal, 32).padding(.top, 12)
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
    }
}

struct Waveform: View {
    var level: Float
    var phase: Double
    private let bars = 32

    /// 基础呼吸波 + 音量放大;phase 为时间戳,由 TimelineView 逐帧驱动
    private func height(_ i: Int) -> CGFloat {
        let x: Double = Double(i) / Double(bars)
        let env: Double = sin(x * .pi)
        let wave: Double = (sin(x * 7 + phase * 5) + 1) / 2
        let wave2: Double = (sin(x * 13 - phase * 8) + 1) / 2
        let boosted: Double = min(1, pow(Double(level), 0.6) * 1.3)
        let base: Double = 0.08 + env * (0.18 + 0.12 * wave)
        let voice: Double = env * boosted * (0.4 + 0.3 * wave2)
        return max(4, CGFloat(100 * (base + voice)))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<bars, id: \.self) { i in
                let env = sin(Double(i) / Double(bars) * .pi)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.brand.opacity(0.45 + env * 0.55))
                    .frame(width: 4, height: height(i))
            }
        }
    }
}
