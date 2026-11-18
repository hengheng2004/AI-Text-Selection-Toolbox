import Foundation
import Darwin

/// 命令行小工具：拉取 OpenAI 兼容服务的 `/models` 列表。
///
/// 用法示例：
///   swift run models-list -b https://api.deepseek.com/v1 -k sk-xxx
///   LLM_API_KEY=sk-xxx swift run models-list -b https://api.openai.com/v1
@main
struct ModelsListCLI {

    // MARK: - 参数

    private struct Options {
        var baseURL: String?
        var apiKey: String?
        var printJSON = false
        var verbose = false
        var idsOnly = false
        var timeout: TimeInterval = 20
    }

    private static let usage = """
    models-list — 拉取 OpenAI 兼容服务的可用模型列表

    用法:
      models-list [选项] [base_url] [api_key]
      swift run models-list -b https://api.deepseek.com/v1 -k sk-xxx

    选项:
      -b, --base-url <url>   API Base URL（可带 /v1，也可直接填到 /chat/completions）
      -k, --api-key <key>    API Key；不传则读环境变量，仍没有则交互输入
          --json             打印服务端返回的原始 JSON
      -v, --verbose          额外显示 owned_by / 创建时间
          --ids              只输出模型 ID（输出到管道时自动启用）
          --timeout <秒>     请求超时，默认 20
      -h, --help             显示帮助

    环境变量:
      LLM_BASE_URL / LLM_API_KEY（也支持 OPENAI_BASE_URL / OPENAI_API_KEY）

    示例:
      models-list https://api.deepseek.com/v1 sk-xxxx
      LLM_API_KEY=sk-xxx models-list -b https://api.deepseek.com/v1 | pbcopy
    """

    // MARK: - 入口

    static func main() async {
        var options = Options()
        var positional: [String] = []

        var index = 0
        let arguments = Array(CommandLine.arguments.dropFirst())
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "-h", "--help":
                print(usage)
                exit(0)
            case "-b", "--base-url":
                index += 1
                guard index < arguments.count else { fail("--base-url 后面缺少值") }
                options.baseURL = arguments[index]
            case "-k", "--api-key":
                index += 1
                guard index < arguments.count else { fail("--api-key 后面缺少值") }
                options.apiKey = arguments[index]
            case "--json":
                options.printJSON = true
            case "-v", "--verbose":
                options.verbose = true
            case "--ids":
                options.idsOnly = true
            case "--timeout":
                index += 1
                guard index < arguments.count, let seconds = TimeInterval(arguments[index]), seconds > 0 else {
                    fail("--timeout 后面需要一个大于 0 的秒数")
                }
                options.timeout = seconds
            default:
                if argument.hasPrefix("-") {
                    fail("未知选项：\(argument)\n\n\(usage)")
                }
                positional.append(argument)
            }
            index += 1
        }

        // 位置参数不要求顺序：带 :// 的当 Base URL，其余的当 API Key。
        var remaining = positional
        if options.baseURL == nil, let urlIndex = remaining.firstIndex(where: { $0.contains("://") }) {
            options.baseURL = remaining.remove(at: urlIndex)
        }
        if options.apiKey == nil, !remaining.isEmpty {
            options.apiKey = remaining.removeFirst()
        }
        if options.baseURL == nil, !remaining.isEmpty {
            options.baseURL = remaining.removeFirst()
        }
        guard remaining.isEmpty else { fail("多余的参数：\(remaining.joined(separator: " "))") }

        let environment = ProcessInfo.processInfo.environment
        if options.baseURL == nil {
            options.baseURL = environment["LLM_BASE_URL"] ?? environment["OPENAI_BASE_URL"]
        }
        if options.apiKey == nil {
            options.apiKey = environment["LLM_API_KEY"] ?? environment["OPENAI_API_KEY"]
        }

        let interactive = isatty(STDIN_FILENO) == 1
        if (options.baseURL ?? "").isEmpty, interactive {
            options.baseURL = prompt("Base URL（例如 https://api.deepseek.com/v1）: ")
        }
        if (options.apiKey ?? "").isEmpty, interactive {
            options.apiKey = promptSecret("API Key（输入不回显，本地服务可直接回车跳过）: ")
        }

        guard let base = options.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !base.isEmpty else {
            fail("缺少 Base URL。\n\n\(usage)")
        }

        let apiKey = options.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard var target = modelsURL(from: base) else {
            fail("Base URL 格式不正确：\(base)")
        }

        // 只填了域名时，多数服务还需要 /v1 前缀；404 时自动补一次。
        var candidates = [target]
        if target.path == "/models", let fallback = URL(string: base.trimmedTrailingSlashes() + "/v1/models") {
            candidates.append(fallback)
        }

        var lastError: String?
        for (offset, url) in candidates.enumerated() {
            target = url
            do {
                let (data, response) = try await fetch(url: url, apiKey: apiKey, timeout: options.timeout)
                if response.statusCode == 404, offset + 1 < candidates.count {
                    lastError = describe(status: response.statusCode, body: data)
                    continue
                }
                render(data: data, status: response.statusCode, options: options)
                return
            } catch let error as URLError {
                lastError = networkMessage(error, url: url)
            } catch {
                lastError = "请求失败：\(error.localizedDescription)"
            }
        }

        fail(lastError ?? "请求失败")
    }

    // MARK: - 请求

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private static func fetch(url: URL, apiKey: String, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("models-list/1.0", forHTTPHeaderField: "User-Agent")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    // MARK: - 输出

    private static func render(data: Data, status: Int, options: Options) {
        guard (200..<300).contains(status) else {
            fail(describe(status: status, body: data))
        }

        if options.printJSON {
            if let object = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: pretty, encoding: .utf8) {
                print(text)
            } else {
                print(String(data: data, encoding: .utf8) ?? "")
            }
            return
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            let preview = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
            fail("返回内容不是 JSON：\(preview)")
        }

        var seen = Set<String>()
        let models = extractModels(from: object)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }

        guard !models.isEmpty else {
            let preview = String(data: data, encoding: .utf8)?.prefix(500) ?? ""
            fail("没有解析到模型列表。服务端返回：\n\(preview)")
        }

        let toTerminal = isatty(STDOUT_FILENO) == 1
        if options.idsOnly || (!toTerminal && !options.verbose) {
            for model in models { print(model.id) }
            return
        }

        print("共 \(models.count) 个可用模型\n")
        if options.verbose {
            let width = min(44, models.map { $0.id.count }.max() ?? 0)
            for model in models {
                var line = model.id + String(repeating: " ", count: max(0, width - model.id.count))
                if let owner = model.owner, !owner.isEmpty {
                    line += "  owned_by: \(owner)"
                }
                if let created = model.created, !created.isEmpty {
                    line += "  created: \(created)"
                }
                print(line)
            }
        } else {
            for model in models { print(model.id) }
        }
    }

    // MARK: - 解析（兼容几种常见的返回结构）

    private struct Model {
        let id: String
        var owner: String?
        var created: String?
    }

    private static func extractModels(from value: Any) -> [Model] {
        if let array = value as? [Any] {
            return array.compactMap { model(from: $0) }
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

    private static func model(from value: Any) -> Model? {
        if let text = value as? String {
            let id = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : Model(id: id)
        }
        guard let object = value as? [String: Any] else { return nil }

        let identifier = ["id", "name", "model", "slug"]
            .compactMap { object[$0] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let id = identifier else { return nil }

        let owner = ["owned_by", "owner", "organization", "provider"]
            .compactMap { object[$0] as? String }
            .first { !$0.isEmpty }

        var created: String?
        if let number = object["created"] as? NSNumber ?? object["created_at"] as? NSNumber {
            created = format(unixTime: number.doubleValue)
        } else if let text = object["created"] as? String ?? object["created_at"] as? String {
            created = text
        }

        return Model(id: id, owner: owner, created: created)
    }

    private static func format(unixTime: Double) -> String {
        guard unixTime > 0 else { return "" }
        let seconds = unixTime > 10_000_000_000 ? unixTime / 1000 : unixTime
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - URL / 错误

    private static func modelsURL(from raw: String) -> URL? {
        var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func describe(status: Int, body: Data) -> String {
        let hint: String
        switch status {
        case 401, 403: hint = "API Key 无效或没有权限"
        case 404: hint = "Base URL 不对，或该服务不提供 /models 接口"
        case 405: hint = "该服务不支持用 GET 拉取模型列表"
        case 429: hint = "请求太频繁，被限流了"
        case 500...599: hint = "服务端出错了"
        default: hint = "请求失败"
        }
        let text = String(data: body, encoding: .utf8) ?? ""
        let detail = text.isEmpty ? "" : "\n" + String(text.prefix(500))
        return "\(hint)（HTTP \(status)）\(detail)"
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
        return "\(hint)\n地址：\(url.absoluteString)"
    }

    // MARK: - 交互

    private static func prompt(_ text: String) -> String {
        FileHandle.standardError.write(Data(text.utf8))
        return readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func promptSecret(_ text: String) -> String {
        FileHandle.standardError.write(Data(text.utf8))
        guard isatty(STDIN_FILENO) == 1 else {
            return readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else {
            return readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        var hidden = original
        hidden.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &hidden)
        let value = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        tcsetattr(STDIN_FILENO, TCSANOW, &original)
        FileHandle.standardError.write(Data("\n".utf8))
        return value
    }

    // MARK: - 退出

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("models-list: \(message)\n".utf8))
        exit(1)
    }
}

private extension String {
    func trimmedTrailingSlashes() -> String {
        var copy = self
        while copy.hasSuffix("/") { copy.removeLast() }
        return copy
    }
}