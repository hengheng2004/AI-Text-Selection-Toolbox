import Foundation

struct LLMConfig {
    var baseURL: String
    var apiKey: String
    var model: String
    var targetLanguage: String

    static let defaultBaseURL = "https://api.deepseek.com/v1"
    static let defaultModel = "deepseek-chat"
    static let defaultTargetLanguage = "简体中文"

    static func load() -> LLMConfig {
        let defaults = UserDefaults.standard
        return LLMConfig(
            baseURL: defaults.string(forKey: "baseURL") ?? defaultBaseURL,
            apiKey: Keychain.load() ?? "",
            model: defaults.string(forKey: "model") ?? defaultModel,
            targetLanguage: defaults.string(forKey: "targetLanguage") ?? defaultTargetLanguage
        )
    }

    var isConfigured: Bool {
        !apiKey.trimmed.isEmpty && !model.trimmed.isEmpty && endpointURL != nil
    }

    var endpointURL: URL? {
        var base = baseURL.trimmed
        guard !base.isEmpty else { return nil }
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/chat/completions") {
            return URL(string: base)
        }
        return URL(string: base + "/chat/completions")
    }
}