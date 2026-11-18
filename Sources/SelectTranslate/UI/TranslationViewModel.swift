import SwiftUI

@MainActor
final class TranslationViewModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case loading
        case streaming
        case done
        case failed(String)
    }

    enum VocabState: Equatable {
        case idle
        case loading
        case done
        case failed
    }

    /// 词典查询状态（单个单词模式）
    enum DictState: Equatable {
        case idle
        case loading
        case done
        case failed
    }

    @Published var original = ""
    @Published var translation = ""
    @Published var status: Status = .idle
    @Published var vocabulary: [VocabWord] = []
    @Published var vocabState: VocabState = .idle
    /// 当前译文来自缓存（没有发请求）
    @Published var isFromCache = false
    /// 选中的是单个单词，走词典模式
    @Published var isWordMode = false
    @Published var dictionary: DictionaryEntry?
    @Published var dictState: DictState = .idle

    private let client = LLMClient()
    private var task: Task<Void, Never>?
    private var vocabTask: Task<Void, Never>?
    private var lastConfig: LLMConfig?

    var isLoading: Bool {
        status == .loading || status == .streaming
    }

    func start(text: String, config: LLMConfig, forceRefresh: Bool = false) {
        task?.cancel()
        task = nil
        vocabTask?.cancel()
        vocabTask = nil

        original = text
        translation = ""
        vocabulary = []
        vocabState = .idle
        dictionary = nil
        dictState = .idle
        status = .loading
        isFromCache = false
        lastConfig = config

        if let word = Self.singleWord(text) {
            isWordMode = true
            lookup(word: word, config: config, forceRefresh: forceRefresh)
            return
        }
        isWordMode = false

        // 缓存 key 用规整后的文本，避免首尾空格/换行导致缓存穿透
        let cacheText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let wantsVocabulary = UserDefaults.standard.object(forKey: "showVocabulary") as? Bool ?? true
        let wantsVocab = wantsVocabulary && Self.looksEnglish(text)

        // 命中缓存：译文和生词直接给，一个请求都不发
        if !forceRefresh, let cached = TranslationCache.shared.entry(for: cacheText, config: config) {
            translation = cached.translation
            status = .done
            isFromCache = true
            DebugLog.write("缓存命中：\(text.count) 字符")
            if let words = cached.vocabulary {
                vocabulary = words
                vocabState = .done
            } else if wantsVocab {
                fetchVocabulary(text: cacheText, config: config)
            }
            return
        }

        // 译文和生词并发请求：译文流式先出现，生词后补齐，互不阻塞
        if wantsVocab {
            fetchVocabulary(text: cacheText, config: config)
        }

        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client.streamTranslation(text: text, config: config) { [weak self] delta in
                    guard let self else { return }
                    self.translation += delta
                    if self.status == .loading { self.status = .streaming }
                }
                if !Task.isCancelled {
                    self.status = .done
                    TranslationCache.shared.storeTranslation(self.translation, for: cacheText, config: config)
                    DebugLog.write("翻译完成：\(self.translation.count) 字符")
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.status = .failed(error.localizedDescription)
                DebugLog.write("翻译失败：\(error.localizedDescription)")
            }
        }
    }

    /// 单个单词：查词典式条目（非流式，一次返回）
    private func lookup(word: String, config: LLMConfig, forceRefresh: Bool) {
        if !forceRefresh,
           let cached = TranslationCache.shared.entry(for: word, config: config),
           let entry = cached.dictionary {
            dictionary = entry
            dictState = .done
            status = .done
            isFromCache = true
            DebugLog.write("缓存命中（词典）：\(word)")
            return
        }

        dictState = .loading
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let entry = try await self.client.fetchDictionary(word: word, config: config)
                guard !Task.isCancelled else { return }
                self.dictionary = entry
                self.dictState = .done
                self.status = .done
                TranslationCache.shared.storeDictionary(entry, for: word, config: config)
                DebugLog.write("词典完成：\(entry.senses.count) 个义项")
            } catch {
                guard !Task.isCancelled else { return }
                self.dictState = .failed
                self.status = .failed(error.localizedDescription)
                DebugLog.write("词典失败：\(error.localizedDescription)")
            }
        }
    }

    /// 复制按钮用的文本：单词模式输出整理好的词典条目
    var copyableText: String {
        if let dictionary, !dictionary.senses.isEmpty { return dictionary.plainText }
        return translation
    }

    /// 忽略缓存重新翻译（浮窗上的刷新按钮）
    func retranslate() {
        guard let config = lastConfig, !original.isEmpty else { return }
        start(text: original, config: config, forceRefresh: true)
    }

    private func fetchVocabulary(text: String, config: LLMConfig) {
        vocabState = .loading
        let input = String(text.prefix(3000))
        vocabTask = Task { [weak self] in
            guard let self else { return }
            do {
                let words = try await self.client.fetchVocabulary(text: input, config: config)
                guard !Task.isCancelled else { return }
                self.vocabulary = words
                self.vocabState = .done
                TranslationCache.shared.storeVocabulary(words, for: text, config: config)
                DebugLog.write("生词完成：\(words.count) 个")
            } catch {
                guard !Task.isCancelled else { return }
                self.vocabState = .failed
                DebugLog.write("生词失败：\(error.localizedDescription)")
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        vocabTask?.cancel()
        vocabTask = nil
        if status == .loading || status == .streaming {
            status = .done
        }
        if vocabState == .loading {
            vocabState = .idle
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        vocabTask?.cancel()
        vocabTask = nil
        original = ""
        translation = ""
        vocabulary = []
        vocabState = .idle
        dictionary = nil
        dictState = .idle
        isWordMode = false
        status = .idle
        isFromCache = false
        lastConfig = nil
    }

    /// 判断是不是“单个英文单词”：允许连字符和撇号，最多 40 字符
    static func singleWord(_ text: String) -> String? {
        // 选区经常带标点，比如 "robust," 或 “robust.”，先把首尾标点去掉
        let edgePunctuation = CharacterSet(charactersIn: ".,;:!?\"“”‘’()[]{}<>《》、，。！？；：")
        let core = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: edgePunctuation)
        guard !core.isEmpty, core.count <= 40 else { return nil }

        let allowed = CharacterSet.letters.union(CharacterSet(charactersIn: "-'’-"))
        guard core.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }

        let latin = core.unicodeScalars.filter {
            ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122)
        }.count
        guard latin >= 2 else { return nil }
        return core
    }

    /// 只在明显是英文文本时才请求生词，避免翻译中文时白花一次请求
    private static func looksEnglish(_ text: String) -> Bool {
        var latin = 0
        var cjk = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 65...90, 97...122: latin += 1
            case 0x4E00...0x9FFF: cjk += 1
            default: break
            }
        }
        return latin >= 20 && latin > cjk * 2
    }
}