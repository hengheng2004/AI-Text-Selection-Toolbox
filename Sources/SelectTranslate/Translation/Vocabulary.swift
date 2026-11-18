import Foundation

struct VocabWord: Identifiable, Codable, Equatable {
    let word: String
    let phonetic: String?
    let pos: String?
    let meaning: String
    let level: String?

    var id: String { word + "|" + meaning }

    /// 归一化后的难度标签（雅思 / 托福 / 学术 / 常用）
    var levelTag: String? { normalizeLevelTag(level) }
}

enum VocabPrompt {
    static let system = """
    你是一位英语词汇教学助手。用户会给出一段英文原文，请挑出其中对中文母语学习者较难的单词或短语，\
    重点覆盖雅思、托福、学术英语（AWL）词汇。

    只输出一个 JSON 数组，不要 markdown 代码块，不要任何解释文字。数组元素格式：
    {"word": "原文中的词形", "phonetic": "音标，没有就空字符串", "pos": "词性缩写如 n./v./adj.", "meaning": "结合本文语境的中文释义", "level": "IELTS 或 TOEFL 或 学术 或 常用"}

    规则：
    1. 最多 8 个，按难度从高到低排序。
    2. 跳过专有名词和过于简单的词（the, make, good, people 等）。
    3. meaning 要贴合当前语境，只给一个最合适的释义，不要罗列所有义项。
    4. 短语（如 take into account）也可以列出，word 字段写原短语。
    5. 如果原文太短或没有值得学的词，输出空数组 []。
    """
}

enum VocabParser {
    static func parse(_ raw: String) throws -> [VocabWord] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 容忍模型偶尔包上的 markdown 代码块
        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if let fence = text.range(of: "```", options: .backwards) {
                text = String(text[..<fence.lowerBound])
            }
        }

        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"),
              start < end else {
            throw LLMError(message: "生词结果不是合法 JSON：\(raw.prefix(120))")
        }

        let json = String(text[start...end])
        guard let data = json.data(using: .utf8) else {
            throw LLMError(message: "生词结果编码失败")
        }

        do {
            return try JSONDecoder().decode([VocabWord].self, from: data)
        } catch {
            throw LLMError(message: "生词 JSON 解析失败：\(error.localizedDescription)")
        }
    }
}