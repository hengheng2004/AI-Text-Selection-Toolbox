import Foundation

/// 单个单词的词典式条目
struct DictionarySense: Identifiable, Codable, Equatable {
    let pos: String?
    let meaning: String
    let example: String?
    let exampleTranslation: String?

    var id: String { (pos ?? "") + "|" + meaning + "|" + (example ?? "") }
}

struct DictionaryEntry: Codable, Equatable {
    let word: String
    let phonetic: String?
    let level: String?
    let senses: [DictionarySense]
    let synonyms: [String]?
    let note: String?

    /// 归一化后的难度标签（雅思 / 托福 / 学术 / 常用）
    var levelTag: String? { normalizeLevelTag(level) }

    var plainText: String {
        var lines: [String] = []
        var head = word
        if let phonetic, !phonetic.isEmpty { head += "  \(phonetic)" }
        lines.append(head)
        for (index, sense) in senses.enumerated() {
            var line = "\(index + 1). "
            if let pos = sense.pos, !pos.isEmpty { line += "\(pos) " }
            line += sense.meaning
            lines.append(line)
            if let example = sense.example, !example.isEmpty {
                lines.append("   \(example)")
            }
            if let translation = sense.exampleTranslation, !translation.isEmpty {
                lines.append("   \(translation)")
            }
        }
        if let synonyms, !synonyms.isEmpty {
            lines.append("近义词：" + synonyms.joined(separator: "、"))
        }
        if let note, !note.isEmpty {
            lines.append("提示：" + note)
        }
        return lines.joined(separator: "\n")
    }

    init(word: String, phonetic: String?, level: String?, senses: [DictionarySense], synonyms: [String]?, note: String?) {
        self.word = word
        self.phonetic = phonetic
        self.level = level
        self.senses = senses
        self.synonyms = synonyms
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        word = try container.decodeIfPresent(String.self, forKey: .word) ?? ""
        phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic)
        level = try container.decodeIfPresent(String.self, forKey: .level)
        senses = try container.decodeIfPresent([DictionarySense].self, forKey: .senses) ?? []
        synonyms = try container.decodeIfPresent([String].self, forKey: .synonyms)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

enum DictionaryPrompt {
    static let system = """
    你是一位英汉词典编纂助手。用户会给出一个英文单词，请输出词典式条目。

    只输出一个 JSON 对象，不要 markdown 代码块，不要任何解释文字。格式：
    {
      "word": "原词",
      "phonetic": "带斜杠的国际音标，例如 /rəʊˈbʌst/",
      "level": "IELTS 或 TOEFL 或 学术 或 常用",
      "senses": [
        {"pos": "n. 或 v. 或 adj. 等", "meaning": "一个最常用的中文释义", "example": "不超过 20 词的英文例句", "exampleTranslation": "例句的中文翻译"}
      ],
      "synonyms": ["2~4 个近义词"],
      "note": "常见搭配、易混词或用法提醒，一句话，没有就空字符串"
    }

    规则：
    1. senses 给 1~4 条，按使用频率从高到低，每条只讲一个义项，不要罗列同义词堆砌。
    2. meaning 要像词典释义一样简洁准确，量词、介词搭配要写清楚。
    3. example 必须体现该义项的典型用法，句子里要包含这个词的变形。
    4. 如果是生僻词、专有名词或拼写错误，senses 输出空数组，并在 note 里说明。
    """
}

enum DictionaryParser {
    static func parse(_ raw: String) throws -> DictionaryEntry {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if let fence = text.range(of: "```", options: .backwards) {
                text = String(text[..<fence.lowerBound])
            }
        }

        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else {
            throw LLMError(message: "词典结果不是合法 JSON：\(raw.prefix(120))")
        }

        let json = String(text[start...end])
        guard let data = json.data(using: .utf8) else {
            throw LLMError(message: "词典结果编码失败")
        }

        do {
            return try JSONDecoder().decode(DictionaryEntry.self, from: data)
        } catch {
            throw LLMError(message: "词典 JSON 解析失败：\(error.localizedDescription)")
        }
    }
}

/// 难度标签统一归一化
func normalizeLevelTag(_ level: String?) -> String? {
    guard let level, !level.isEmpty else { return nil }
    let upper = level.uppercased()
    if level.contains("雅思") || upper.contains("IELTS") { return "雅思" }
    if level.contains("托福") || upper.contains("TOEFL") { return "托福" }
    if level.contains("学术") || upper.contains("AWL") || upper.contains("ACADEMIC") { return "学术" }
    return level
}