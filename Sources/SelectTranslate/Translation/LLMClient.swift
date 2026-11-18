import Foundation

struct LLMError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 一条聊天消息，解释功能的多轮对话用
struct ChatMessage: Equatable {
    enum Role: String {
        case system
        case user
        case assistant
    }

    let role: Role
    var content: String

    init(_ role: Role, _ content: String) {
        self.role = role
        self.content = content
    }

    var payload: [String: String] {
        ["role": role.rawValue, "content": content]
    }
}

/// OpenAI 兼容客户端，一套代码适配 DeepSeek / OpenAI / Kimi / GLM / Ollama 等
final class LLMClient {

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta
        }
        let choices: [Choice]
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    // MARK: - 翻译（流式）

    func streamTranslation(
        text: String,
        config: LLMConfig,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws {
        let request = try makeRequest(
            messages: [
                ["role": "system", "content": PromptBuilder.systemPrompt(targetLanguage: config.targetLanguage)],
                ["role": "user", "content": text]
            ],
            stream: true,
            temperature: 0.2,
            timeout: 90,
            config: config
        )

        try await stream(request: request, onDelta: onDelta)
    }

    // MARK: - 通用多轮对话（流式，解释功能）

    func streamChat(
        messages: [ChatMessage],
        config: LLMConfig,
        temperature: Double = 0.4,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws {
        let request = try makeRequest(
            messages: messages.map(\.payload),
            stream: true,
            temperature: temperature,
            timeout: 120,
            config: config
        )

        try await stream(request: request, onDelta: onDelta)
    }

    /// 统一的 SSE 处理：翻译和解释共用
    private func stream(
        request: URLRequest,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError(message: "收到了无效的响应")
        }

        guard http.statusCode == 200 else {
            var detail = ""
            for try await line in bytes.lines {
                detail += line
                if detail.count > 600 { break }
            }
            throw Self.httpError(status: http.statusCode, body: detail)
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8) else { continue }
            if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
               let delta = chunk.choices.first?.delta.content,
               !delta.isEmpty {
                await onDelta(delta)
            }
        }
    }

    // MARK: - 普通补全（非流式）

    func complete(
        system: String,
        user: String,
        config: LLMConfig,
        temperature: Double = 0.2
    ) async throws -> String {
        let request = try makeRequest(
            messages: [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            stream: false,
            temperature: temperature,
            timeout: 60,
            config: config
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Self.httpError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = decoded.choices.first?.message.content,
              !content.isEmpty else {
            let preview = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw LLMError(message: "无法解析模型返回：\(preview)")
        }
        return content
    }

    // MARK: - 词典查询（单个单词）

    func fetchDictionary(word: String, config: LLMConfig) async throws -> DictionaryEntry {
        let content = try await complete(
            system: DictionaryPrompt.system,
            user: word,
            config: config,
            temperature: 0.2
        )
        return try DictionaryParser.parse(content)
    }

    // MARK: - 生词提取

    func fetchVocabulary(text: String, config: LLMConfig) async throws -> [VocabWord] {
        let content = try await complete(
            system: VocabPrompt.system,
            user: text,
            config: config,
            temperature: 0.3
        )
        return try VocabParser.parse(content)
    }

    // MARK: - 辅助

    private func makeRequest(
        messages: [[String: String]],
        stream: Bool,
        temperature: Double,
        timeout: TimeInterval,
        config: LLMConfig
    ) throws -> URLRequest {
        guard let url = config.endpointURL else {
            throw LLMError(message: "Base URL 格式不正确")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": config.model,
            "stream": stream,
            "temperature": temperature,
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func httpError(status: Int, body: String) -> LLMError {
        let hint: String
        switch status {
        case 401, 403: hint = "API Key 无效或没有权限"
        case 404: hint = "Base URL 或模型名不对"
        case 429: hint = "请求太频繁，被限流了"
        default: hint = "服务端返回错误"
        }
        let detail = body.isEmpty ? "" : "\n" + String(body.prefix(300))
        return LLMError(message: "\(hint)（HTTP \(status)）\(detail)")
    }
}