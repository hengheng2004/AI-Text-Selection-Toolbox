import SwiftUI

/// 生词本条目的持久化模型
struct VocabEntry: Identifiable, Codable, Equatable {
    let id: String
    let word: String
    let phonetic: String?
    let pos: String?
    let meaning: String
    let level: String?
    let context: String?
    let addedAt: Date

    var levelTag: String? { normalizeLevelTag(level) }

    init(
        id: String = UUID().uuidString,
        word: String,
        phonetic: String?,
        pos: String?,
        meaning: String,
        level: String?,
        context: String?,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.word = word
        self.phonetic = phonetic
        self.pos = pos
        self.meaning = meaning
        self.level = level
        self.context = context
        self.addedAt = addedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        word = try container.decodeIfPresent(String.self, forKey: .word) ?? ""
        phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic)
        pos = try container.decodeIfPresent(String.self, forKey: .pos)
        meaning = try container.decodeIfPresent(String.self, forKey: .meaning) ?? ""
        level = try container.decodeIfPresent(String.self, forKey: .level)
        context = try container.decodeIfPresent(String.self, forKey: .context)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }
}

/// 生词本：本地 JSON 存储，随时可增删
@MainActor
final class VocabBook: ObservableObject {
    static let shared = VocabBook()

    @Published private(set) var entries: [VocabEntry] = []

    private let fileURL: URL
    private var loaded = false

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        fileURL = base.appendingPathComponent("SelectTranslate/vocab-book.json", isDirectory: false)
        loadIfNeeded()
    }

    var storagePath: String { fileURL.path }

    func contains(_ word: String) -> Bool {
        loadIfNeeded()
        let target = word.lowercased()
        return entries.contains { $0.word.lowercased() == target }
    }

    /// 收录一个生词，已存在则返回 false
    @discardableResult
    func add(_ word: VocabWord, context: String?) -> Bool {
        add(
            VocabEntry(
                word: word.word,
                phonetic: word.phonetic,
                pos: word.pos,
                meaning: word.meaning,
                level: word.level,
                context: trimmedContext(context)
            )
        )
    }

    /// 收录一个词典查询到的单词（取第一个义项）
    @discardableResult
    func add(_ entry: DictionaryEntry, context: String?) -> Bool {
        let first = entry.senses.first
        return add(
            VocabEntry(
                word: entry.word,
                phonetic: entry.phonetic,
                pos: first?.pos,
                meaning: first?.meaning ?? "",
                level: entry.level,
                context: trimmedContext(context)
            )
        )
    }

    @discardableResult
    func add(_ entry: VocabEntry) -> Bool {
        loadIfNeeded()
        guard !entry.word.trimmed.isEmpty else { return false }
        guard !contains(entry.word) else { return false }
        entries.insert(entry, at: 0)
        save()
        DebugLog.write("生词本收录：\(entry.word)")
        return true
    }

    func remove(id: String) {
        loadIfNeeded()
        entries.removeAll { $0.id == id }
        save()
    }

    func remove(word: String) {
        loadIfNeeded()
        let target = word.lowercased()
        entries.removeAll { $0.word.lowercased() == target }
        save()
    }

    func clear() {
        entries = []
        loaded = true
        try? FileManager.default.removeItem(at: fileURL)
        DebugLog.write("生词本已清空")
    }

    private func trimmedContext(_ context: String?) -> String? {
        guard let context else { return nil }
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(300))
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([VocabEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        // 生词本文件很小，同步写入可以保证「添加/删除」按调用顺序落盘，
        // 避免并发 detached 写把已经删掉的词又写回来。
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}