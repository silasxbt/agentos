import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechService: NSObject, ObservableObject {
    @Published var transcript = ""
    @Published var isListening = false
    @Published var level: Float = 0          // 0~1 音量,用于波形动画
    @Published var errorMessage: String?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var silenceTimer: Timer?
    var onFinal: ((String) -> Void)?

    override init() {
        super.init()
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")) ?? SFSpeechRecognizer()
    }

    func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard speech == .authorized else { errorMessage = "语音识别未授权"; return false }
        let mic: Bool
        if #available(iOS 17.0, *) { mic = await AVAudioApplication.requestRecordPermission() }
        else { mic = await withCheckedContinuation { c in AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) } } }
        if !mic { errorMessage = "麦克风未授权" }
        return mic
    }

    func start() {
        guard !isListening else { return }
        transcript = ""; errorMessage = nil
        guard let recognizer, recognizer.isAvailable else { errorMessage = "语音识别当前不可用(模拟器请使用手动输入)"; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if #available(iOS 16, *) { req.addsPunctuation = false }
            if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = false }
            request = req

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                req.append(buffer)
                let rms = Self.rms(buffer)
                Task { @MainActor in self?.level = min(1, rms * 12) }
            }
            engine.prepare(); try engine.start()
            isListening = true

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        self.resetSilenceTimer()
                        if result.isFinal { self.finish() }
                    }
                    if error != nil, self.isListening { self.finish() }
                }
            }
            resetSilenceTimer()
        } catch {
            errorMessage = "无法启动录音: \(error.localizedDescription)"
            stopEngine()
        }
    }

    /// 停顿 1.6s 视为说完
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isListening, !self.transcript.isEmpty else { return }
                self.finish()
            }
        }
    }

    func finish() {
        guard isListening else { return }
        stopEngine()
        let text = transcript
        if !text.isEmpty { onFinal?(text) }
    }

    func cancel() { stopEngine(); transcript = "" }

    private func stopEngine() {
        silenceTimer?.invalidate()
        isListening = false; level = 0
        request?.endAudio(); task?.cancel(); task = nil; request = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength); guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        return sqrt(sum / Float(n))
    }
}
