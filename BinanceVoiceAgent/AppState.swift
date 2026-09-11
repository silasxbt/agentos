import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Stage: Equatable {
        case idle
        case listening
        case parsing
        case confirm
        case authenticating
        case submitting
        case success(FilledOrder)
        case failed(String)

        static func == (a: Stage, b: Stage) -> Bool {
            switch (a, b) {
            case (.idle, .idle), (.listening, .listening), (.parsing, .parsing), (.confirm, .confirm),
                 (.authenticating, .authenticating), (.submitting, .submitting): return true
            case (.success(let x), .success(let y)): return x.id == y.id
            case (.failed(let x), .failed(let y)): return x == y
            default: return false
            }
        }
    }

    @Published var stage: Stage = .idle
    @Published var draft: TradeOrder?
    @Published var agentNotes: [String] = []
    @Published var confidence: Double = 0
    @Published var manualText = ""

    let speech = SpeechService()
    let orders = OrderService()
    private let parser = CommandParser()

    private init() {
        speech.onFinal = { [weak self] text in self?.handleTranscript(text) }
    }

    // 来自 Action Button / App Intent
    func triggerListening() {
        Task {
            guard await speech.requestPermissions() else { stage = .idle; return }
            startListening()
        }
    }

    func startListening() {
        draft = nil; agentNotes = []
        stage = .listening
        speech.start()
        if speech.errorMessage != nil { stage = .idle }
    }

    func stopListening() { speech.finish() }

    func cancelListening() { speech.cancel(); stage = .idle }

    func handleTranscript(_ text: String) {
        stage = .parsing
        Task {
            try? await Task.sleep(for: .milliseconds(600))   // agent "思考"
            let r = parser.parse(text)
            draft = r.order; agentNotes = r.notes; confidence = r.confidence
            stage = .confirm
        }
    }

    func submitManual() {
        let t = manualText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        manualText = ""
        handleTranscript(t)
    }

    /// 用户点击"提交" → Face ID → 下单 → 通知
    func confirmAndSubmit() {
        guard let order = draft, order.missingFields.isEmpty else { return }
        stage = .authenticating
        Task {
            let outcome = await BiometricService.authenticate(reason: "确认下单:\(order.summary)")
            switch outcome {
            case .cancelled: stage = .confirm
            case .failed(let msg): stage = .failed(msg)
            case .success:
                stage = .submitting
                do {
                    let filled = try await orders.submit(order)
                    NotificationService.shared.notifyFilled(filled)
                    stage = .success(filled)
                } catch {
                    NotificationService.shared.notifyFailed(order, reason: error.localizedDescription)
                    stage = .failed(error.localizedDescription)
                }
            }
        }
    }

    func reset() { draft = nil; agentNotes = []; stage = .idle }
}
