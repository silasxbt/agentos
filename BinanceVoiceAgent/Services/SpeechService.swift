import Foundation
import AVFoundation

/// 录音 → 16kHz 单声道 WAV → DashScope qwen-audio-3.0-asr-flash-filetrans 转写。
/// 不使用苹果 SFSpeechRecognizer。对外接口与旧版保持一致。
@MainActor
final class SpeechService: NSObject, ObservableObject {
    @Published var transcript = ""
    @Published var isListening = false
    @Published var isTranscribing = false   // 上传 + 云端转写中
    @Published var level: Float = 0          // 0~1 音量,用于波形动画
    @Published var errorMessage: String?

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var silenceTimer: Timer?
    private var heardSpeech = false
    private var maxTimer: Timer?
    var onFinal: ((String) -> Void)?

    private static let sampleRate: Double = 16_000
    private static let silenceThreshold: Float = 0.06   // rms(放大后)低于此视为静音
    private static let silenceWindow: TimeInterval = 1.6
    private static let maxDuration: TimeInterval = 30

    func requestPermissions() async -> Bool {
        let mic: Bool
        if #available(iOS 17.0, *) { mic = await AVAudioApplication.requestRecordPermission() }
        else { mic = await withCheckedContinuation { c in AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) } } }
        if !mic { errorMessage = "麦克风未授权" }
        return mic
    }

    func start() {
        guard !isListening, !isTranscribing else { return }
        transcript = ""; errorMessage = nil; heardSpeech = false
        // 演示:-demoAudio /path.wav 直接走云端转写,不录音
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-demoAudio"), i + 1 < args.count {
            transcribe(URL(fileURLWithPath: args[i + 1])); return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = engine.inputNode
            let inFormat = input.outputFormat(forBus: 0)
            guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
                errorMessage = "没有可用的麦克风输入(模拟器请使用手动输入)"; stopEngine(); return
            }
            let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Self.sampleRate, channels: 1, interleaved: true)!
            let converter = AVAudioConverter(from: inFormat, to: outFormat)!
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice_\(Int(Date().timeIntervalSince1970)).wav")
            try? FileManager.default.removeItem(at: url)
            file = try AVAudioFile(forWriting: url, settings: outFormat.settings, commonFormat: .pcmFormatInt16, interleaved: true)
            fileURL = url

            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { [weak self] buffer, _ in
                let rms = Self.rms(buffer)
                let ratio = outFormat.sampleRate / inFormat.sampleRate
                let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
                guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: cap) else { return }
                var done = false
                var err: NSError?
                converter.convert(to: out, error: &err) { _, status in
                    if done { status.pointee = .noDataNow; return nil }
                    done = true; status.pointee = .haveData; return buffer
                }
                Task { @MainActor in
                    guard let self, self.isListening else { return }
                    if err == nil, out.frameLength > 0 { try? self.file?.write(from: out) }
                    self.level = min(1, rms * 12)
                    self.onLevel(min(1, rms * 12))
                }
            }
            engine.prepare(); try engine.start()
            isListening = true
            maxTimer = Timer.scheduledTimer(withTimeInterval: Self.maxDuration, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.finish() }
            }
        } catch {
            errorMessage = "无法启动录音: \(error.localizedDescription)"
            stopEngine()
        }
    }

    /// 检测到说话后,静音 1.6s 视为说完
    private func onLevel(_ l: Float) {
        if l > Self.silenceThreshold {
            heardSpeech = true
            silenceTimer?.invalidate()
            silenceTimer = Timer.scheduledTimer(withTimeInterval: Self.silenceWindow, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isListening, self.heardSpeech else { return }
                    self.finish()
                }
            }
        }
    }

    func finish() {
        guard isListening else { return }
        stopEngine()
        file = nil
        guard let url = fileURL else { return }
        transcribe(url)
    }

    private func transcribe(_ url: URL) {
        isTranscribing = true
        Task {
            defer { isTranscribing = false }
            do {
                let text = try await DashScopeASR().transcribe(fileURL: url)
                guard !Task.isCancelled, isTranscribing else { return }
                transcript = text
                onFinal?(text)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() { stopEngine(); file = nil; isTranscribing = false; transcript = "" }

    private func stopEngine() {
        silenceTimer?.invalidate(); maxTimer?.invalidate()
        isListening = false; level = 0
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        let n = Int(buffer.frameLength); guard n > 0 else { return 0 }
        var sum: Float = 0
        if let data = buffer.floatChannelData?[0] {
            for i in 0..<n { sum += data[i] * data[i] }
        } else if let data = buffer.int16ChannelData?[0] {
            for i in 0..<n { let v = Float(data[i]) / 32768; sum += v * v }
        } else { return 0 }
        return sqrt(sum / Float(n))
    }
}
