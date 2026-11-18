import SwiftUI

/// 解释收藏的持久化模型：存的是「术语 + 这一轮的提问 + 这一轮的回答」
struct ExplainFavorite: Identifiable, Codable, Equatable {
    let id: String
    /// 对应会话里那条回答消息的 id，用来在浮窗里切换收藏状态
    let messageID: String
    let term: String
    let question: String
    let answer: String
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        messageID: String,
        term: String,
        question: String,
        answer: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.messageID = messageID
        self.term = term
        self.question = question
        self.answer = answer
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        messageID = try container.decodeIfPresent(String.self, forKey: .messageID) ?? ""
        term = try container.decodeIfPresent(String.self, forKey: .term) ?? ""
        question = try container.decodeIfPresent(String.self, forKey: .question) ?? ""
        answer = try container.decodeIfPresent(String.self, forKey: .answer) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    var plainText: String {
        var lines: [String] = []
        if !term.isEmpty { lines.append("术语：\(term)") }
        if !question.isEmpty { lines.append("提问：\(question)") }
        lines.append("")
        lines.append(answer)
        return lines.joined(separator: "\n")
    }
}

/// 解释收藏夹：本地 JSON 存储，和生词本一样同步原子写
@MainActor
final class ExplainFavorites: ObservableObject {
    static let shared = ExplainFavorites()

    @Published private(set) var entries: [ExplainFavorite] = []

    private let fileURL: URL
    private var loaded = false

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        fileURL = base.appendingPathComponent("SelectTranslate/explain-favorites.json", isDirectory: false)
        loadIfNeeded()
    }

    var storagePath: String { fileURL.path }

    func contains(messageID: String) -> Bool {
        loadIfNeeded()
        guard !messageID.isEmpty else { return false }
        return entries.contains { $0.messageID == messageID }
    }

    @discardableResult
    func add(
        messageID: String,
        term: String,
        question: String,
        answer: String
    ) -> Bool {
        loadIfNeeded()
        let body = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        guard !contains(messageID: messageID) else { return false }

        let entry = ExplainFavorite(
            messageID: messageID,
            term: String(term.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)),
            question: String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000)),
            answer: body
        )
        entries.insert(entry, at: 0)
        save()
        DebugLog.write("收藏解释：\(entry.term.prefix(30))")
        return true
    }

    func remove(messageID: String) {
        loadIfNeeded()
        let before = entries.count
        entries.removeAll { $0.messageID == messageID }
        if entries.count != before { save() }
    }

    func remove(id: String) {
        loadIfNeeded()
        let before = entries.count
        entries.removeAll { $0.id == id }
        if entries.count != before { save() }
    }

    func clear() {
        entries = []
        loaded = true
        try? FileManager.default.removeItem(at: fileURL)
        DebugLog.write("解释收藏已清空")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ExplainFavorite].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}