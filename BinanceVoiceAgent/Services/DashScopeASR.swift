import Foundation

/// 阿里云百炼 DashScope 录音文件转写(qwen-audio-3.0-asr-flash-filetrans)。
/// 流程:getPolicy 获取临时上传凭证 → 上传到 OSS → 提交异步转写任务 → 轮询 → 拉取结果 JSON。
struct DashScopeASR {
    static let model = "qwen-audio-3.0-asr-flash-filetrans"
    private static let base = URL(string: "https://dashscope.aliyuncs.com/api/v1")!

    enum ASRError: LocalizedError {
        case missingKey, http(Int, String), badResponse(String), taskFailed(String), emptyText
        var errorDescription: String? {
            switch self {
            case .missingKey: return "未配置 DashScope API Key(Config/Secrets.swift)"
            case .http(let c, let m): return "DashScope HTTP \(c): \(m)"
            case .badResponse(let s): return "DashScope 响应异常: \(s)"
            case .taskFailed(let s): return "转写任务失败: \(s)"
            case .emptyText: return "未识别到语音内容,请重试"
            }
        }
    }

    var apiKey: String
    /// 可通过设置页覆盖 Key;默认读取 Secrets.swift
    init(apiKey: String? = nil) {
        let override = UserDefaults.standard.string(forKey: "dashScopeAPIKey")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.apiKey = apiKey ?? (override.isEmpty ? Secrets.dashScopeAPIKey : override)
    }

    /// 转写本地音频文件,返回整段文本
    func transcribe(fileURL: URL, language: String = "zh") async throws -> String {
        guard !apiKey.isEmpty, apiKey.hasPrefix("sk-"), !apiKey.contains("xxxx") else { throw ASRError.missingKey }
        let ossURL = try await upload(fileURL: fileURL)
        let taskId = try await submit(ossURL: ossURL, language: language)
        let resultURL = try await poll(taskId: taskId)
        return try await fetchText(resultURL)
    }

    // MARK: - 1. 临时文件上传
    private struct Policy: Decodable {
        struct Data: Decodable {
            let policy, signature, upload_dir, upload_host, oss_access_key_id: String
            let x_oss_object_acl, x_oss_forbid_overwrite: String
        }
        let data: Data
    }

    private func upload(fileURL: URL) async throws -> String {
        var comps = URLComponents(url: Self.base.appendingPathComponent("uploads"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "action", value: "getPolicy"), URLQueryItem(name: "model", value: Self.model)]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let p = try await send(req, as: Policy.self).data

        let key = "\(p.upload_dir)/\(fileURL.lastPathComponent)"
        let boundary = "----bnv\(UUID().uuidString)"
        var body = Data()
        func field(_ n: String, _ v: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(n)\"\r\n\r\n\(v)\r\n".data(using: .utf8)!)
        }
        field("OSSAccessKeyId", p.oss_access_key_id)
        field("Signature", p.signature)
        field("policy", p.policy)
        field("x-oss-object-acl", p.x_oss_object_acl)
        field("x-oss-forbid-overwrite", p.x_oss_forbid_overwrite)
        field("key", key)
        field("success_action_status", "200")
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: fileURL))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var up = URLRequest(url: URL(string: p.upload_host)!)
        up.httpMethod = "POST"
        up.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        up.httpBody = body
        let (d, r) = try await URLSession.shared.data(for: up)
        let code = (r as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ASRError.http(code, String(data: d, encoding: .utf8) ?? "OSS upload failed") }
        return "oss://\(key)"
    }

    // MARK: - 2. 提交异步任务
    private struct TaskResp: Decodable {
        struct Output: Decodable {
            struct Result: Decodable { let transcription_url: String?; let subtask_status: String?; let message: String? }
            let task_id: String; let task_status: String
            let results: [Result]?; let message: String?; let code: String?
        }
        let output: Output
    }

    private func submit(ossURL: String, language: String) async throws -> String {
        var req = URLRequest(url: Self.base.appendingPathComponent("services/audio/asr/transcription"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("enable", forHTTPHeaderField: "X-DashScope-Async")
        req.setValue("enable", forHTTPHeaderField: "X-DashScope-OssResourceResolve")
        let payload: [String: Any] = [
            "model": Self.model,
            "input": ["file_url": ossURL],
            "parameters": ["language": language, "enable_itn": true, "channel_id": [0]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try await send(req, as: TaskResp.self).output.task_id
    }

    // MARK: - 3. 轮询
    private func poll(taskId: String) async throws -> URL {
        var req = URLRequest(url: Self.base.appendingPathComponent("tasks/\(taskId)"))
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        for _ in 0..<60 {   // 最长约 60s
            let out = try await send(req, as: TaskResp.self).output
            switch out.task_status {
            case "SUCCEEDED":
                guard let s = out.results?.first?.transcription_url, let u = URL(string: s) else {
                    throw ASRError.badResponse(out.results?.first?.message ?? "no transcription_url")
                }
                return u
            case "FAILED", "CANCELED", "UNKNOWN":
                throw ASRError.taskFailed(out.message ?? out.results?.first?.message ?? out.task_status)
            default:
                try await Task.sleep(for: .milliseconds(700))
            }
        }
        throw ASRError.taskFailed("超时")
    }

    // MARK: - 4. 拉取结果
    private struct Transcription: Decodable {
        struct T: Decodable { let text: String }
        let transcripts: [T]
    }

    private func fetchText(_ url: URL) async throws -> String {
        let t = try await send(URLRequest(url: url), as: Transcription.self)
        let text = t.transcripts.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ASRError.emptyText }
        return text
    }

    private func send<T: Decodable>(_ req: URLRequest, as: T.Type) async throws -> T {
        let (d, r) = try await URLSession.shared.data(for: req)
        let code = (r as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ASRError.http(code, String(data: d, encoding: .utf8) ?? "") }
        do { return try JSONDecoder().decode(T.self, from: d) }
        catch { throw ASRError.badResponse(String(data: d, encoding: .utf8)?.prefix(200).description ?? "\(error)") }
    }
}
