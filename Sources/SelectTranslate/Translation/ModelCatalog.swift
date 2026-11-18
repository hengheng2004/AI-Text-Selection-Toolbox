import Foundation

enum ModelCatalogError: LocalizedError {
    case invalidBaseURL
    case http(status: Int, detail: String)
    case invalidResponse(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Base URL 格式不正确，需要以 http:// 或 https:// 开头"
        case let .http(status, detail):
            let hint: String
            switch status {
            case 401, 403: hint = "API Key 无效或没有权限"
            case 404: hint = "Base URL 不对，或该服务不提供 /models 接口"
            case 405: hint = "该服务不支持拉取模型列表"
            case 429: hint = "请求太频繁，被限流了"
            case 500...599: hint = "服务端出错了"
            default: hint = "请求失败"
            }
            return "\(hint)（HTTP \(status)）\(detail)"
        case let .invalidResponse(preview):
            return "无法解析服务端返回：\(preview)"
        case let .network(message):
            return message
        }
    }
}

/// 从 OpenAI 兼容服务的 `/models` 接口拉取当前 Key 可用的模型。
enum ModelCatalog {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    static func isValidBaseURL(_ raw: String) -> Bool {
        endpointURL(from: raw) != nil
    }

    static func fetchModels(
        baseURL: String,
        apiKey: String,
        timeout: TimeInterval = 20
    ) async throws -> [String] {
        guard let primary = endpointURL(from: baseURL) else {
            throw ModelCatalogError.invalidBaseURL
        }

        // 只填域名时，多数服务还需要 /v1 前缀；404 时自动补一次。
        var candidates = [primary]
        if primary.path == "/models" {
            var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            while base.hasSuffix("/") { base.removeLast() }
            if let fallback = URL(string: base + "/v1/models") {
                candidates.append(fallback)
            }
        }

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var lastError: ModelCatalogError = .invalidBaseURL

        for (index, url) in candidates.enumerated() {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = timeout
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("SelectTranslate/1.0", forHTTPHeaderField: "User-Agent")
            if !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw ModelCatalogError.invalidResponse("收到了无效的响应")
                }
                if http.statusCode == 404, index + 1 < candidates.count {
                    lastError = httpError(status: 404, data: data)
                    continue
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw httpError(status: http.statusCode, data: data)
                }
                return try parseModels(from: data)
            } catch let error as URLError {
                if error.code == .cancelled { throw CancellationError() }
                throw ModelCatalogError.network(networkMessage(error, url: url))
            }
        }

        throw lastError
    }

    // MARK: - URL

    private static func endpointURL(from raw: String) -> URL? {
        var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/chat/completions") {
            base.removeLast("/chat/completions".count)
        }

        let address = base.hasSuffix("/models") ? base : base + "/models"
        guard let url = URL(string: address),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    // MARK: - 解析

    private static func parseModels(from data: Data) throws -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            let preview = String((String(data: data, encoding: .utf8) ?? "").prefix(200))
            throw ModelCatalogError.invalidResponse(preview)
        }

        var seen = Set<String>()
        return extractModels(from: object)
            .filter { seen.insert($0).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// 兼容 `{"data":[...]}`、`{"models":[...]}`、根数组等常见结构。
    private static func extractModels(from value: Any) -> [String] {
        if let array = value as? [Any] {
            return array.compactMap { modelID(from: $0) }
        }
        guard let object = value as? [String: Any] else { return [] }
        for key in ["data", "models", "result", "results", "items"] {
            if let nested = object[key] {
                let found = extractModels(from: nested)
                if !found.isEmpty { return found }
            }
        }
        return []
    }

    private static func modelID(from value: Any) -> String? {
        if let text = value as? String {
            let id = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : id
        }
        guard let object = value as? [String: Any] else { return nil }
        return ["id", "name", "model", "slug"]
            .compactMap { object[$0] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    // MARK: - 错误

    private static func httpError(status: Int, data: Data) -> ModelCatalogError {
        let text = String(data: data, encoding: .utf8) ?? ""
        let detail = text.isEmpty ? "" : "\n" + String(text.prefix(300))
        return .http(status: status, detail: detail)
    }

    private static func networkMessage(_ error: URLError, url: URL) -> String {
        let hint: String
        switch error.code {
        case .timedOut: hint = "请求超时"
        case .cannotFindHost, .dnsLookupFailed: hint = "找不到主机"
        case .cannotConnectToHost: hint = "连不上服务器"
        case .notConnectedToInternet: hint = "网络未连接"
        case .secureConnectionFailed, .serverCertificateUntrusted: hint = "TLS 握手失败"
        default: hint = "网络错误：\(error.localizedDescription)"
        }
        return "\(hint)：\(url.absoluteString)"
    }
}