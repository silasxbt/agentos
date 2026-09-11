import Foundation
import LocalAuthentication

enum BiometricService {
    enum Outcome { case success, cancelled, failed(String) }

    static var kindName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "设备密码"
        }
    }

    static func authenticate(reason: String) async -> Outcome {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "取消"
        var err: NSError?
        // 优先生物识别;不可用时回退到设备密码(模拟器未录入 Face ID 时也能演示)
        let policy: LAPolicy = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
            ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        do {
            let ok = try await ctx.evaluatePolicy(policy, localizedReason: reason)
            return ok ? .success : .failed("验证未通过")
        } catch let e as LAError {
            switch e.code {
            case .userCancel, .systemCancel, .appCancel: return .cancelled
            case .passcodeNotSet, .biometryNotAvailable, .biometryNotEnrolled:
                return .failed("设备未设置 Face ID / 密码,无法确认交易")
            default: return .failed(e.localizedDescription)
            }
        } catch { return .failed(error.localizedDescription) }
    }
}
