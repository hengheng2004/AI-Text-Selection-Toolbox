import Foundation
import CryptoKit

struct CacheEntry: Codable {
    var translation: String
    var vocabulary: [VocabWord]?
    var dictionary: DictionaryEntry?
    var updatedAt: Date

    init(translation: String = "", vocabulary: [VocabWord]? = nil, dictionary: DictionaryEntry? = nil, updatedAt: Date = Date()) {
        self.translation = translation
        self.vocabulary = vocabulary
        self.dictionary = dictionary
        self.updatedAt = updatedAt
    }

    // 旧缓存文件没有 dictionary 字段，这里做兼容解码
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        translation = try container.decodeIfPresent(String.self, forKey: .translation) ?? ""
        vocabulary = try container.decodeIfPresent([VocabWord].self, forKey: .vocabulary)
        dictionary = try container.decodeIfPresent(DictionaryEntry.self, forKey: .dictionary)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

/// 翻译结果缓存：同一段文字 + 同样的模型配置，直接复用上次的译文和生词。
/// 存在 `~/Library/Application Support/SelectTranslate/translation-cache.json`，
/// 最多保留 300 条，超出后按最近使用时间淘汰。
@MainActor
final class TranslationCache {
    static let shared = TranslationCache()

    private var entries: [String: CacheEntry] = [:]
    private var loaded = false
    private let fileURL: URL
    private let maxEntries = 300

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        fileURL = base.appendingPathComponent("SelectTranslate/translation-cache.json", isDirectory: false)
    }

    var count: Int {
        loadIfNeeded()
        return entries.count
    }

    func entry(for text: String, config: LLMConfig) -> CacheEntry? {
        loadIfNeeded()
        guard let entry = entries[key(text, config)] else { return nil }
        guard !entry.translation.isEmpty || entry.dictionary != nil else { return nil }
        return entry
    }

    func storeTranslation(_ translation: String, for text: String, config: LLMConfig) {
        guard !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        loadIfNeeded()
        let k = key(text, config)
        var entry = entries[k] ?? CacheEntry()
        entry.translation = translation
        entry.updatedAt = Date()
        entries[k] = entry
        trimAndSave()
    }

    func storeVocabulary(_ vocabulary: [VocabWord], for text: String, config: LLMConfig) {
        loadIfNeeded()
        let k = key(text, config)
        var entry = entries[k] ?? CacheEntry()
        entry.vocabulary = vocabulary
        entry.updatedAt = Date()
        entries[k] = entry
        trimAndSave()
    }

    func storeDictionary(_ entry: DictionaryEntry, for text: String, config: LLMConfig) {
        loadIfNeeded()
        let k = key(text, config)
        var cached = entries[k] ?? CacheEntry()
        cached.dictionary = entry
        cached.updatedAt = Date()
        entries[k] = cached
        trimAndSave()
    }

    func clear() {
        entries = [:]
        loaded = true
        try? FileManager.default.removeItem(at: fileURL)
        DebugLog.write("翻译缓存已清空")
    }

    // MARK: - 内部

    private func key(_ text: String, _ config: LLMConfig) -> String {
        let raw = "\(config.baseURL)\u{1F}\(config.model)\u{1F}\(config.targetLanguage)\u{1F}\(text)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else { return }
        entries = decoded
    }

    private func trimAndSave() {
        if entries.count > maxEntries {
            let kept = entries.sorted { $0.value.updatedAt > $1.value.updatedAt }.prefix(maxEntries)
            entries = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
        let snapshot = entries
        let url = fileURL
        Task.detached(priority: .utility) {
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}