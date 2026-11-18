import SwiftUI

/// 解释浮窗的状态：一次临时会话，不落盘；只有用户手动收藏的问答会持久化
@MainActor
final class ExplainViewModel: ObservableObject {
    struct Message: Identifiable, Equatable {
        let id: String
        let role: ChatMessage.Role
        var content: String
        var isStreaming: Bool

        init(
            id: String = UUID().uuidString,
            role: ChatMessage.Role,
            content: String,
            isStreaming: Bool = false
        ) {
            self.id = id
            self.role = role
            self.content = content
            self.isStreaming = isStreaming
        }
    }

    @Published var term = ""
    @Published var messages: [Message] = []
    @Published var input = ""
    @Published var isStreaming = false
    @Published var errorText: String?

    private let client = LLMClient()
    private var task: Task<Void, Never>?
    private var history: [ChatMessage] = []
    private var config: LLMConfig?
    /// 会话代次：旧请求回来时直接丢弃，避免覆盖新会话
    private var generation = 0

    var canSend: Bool {
        !isStreaming && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 会话

    func start(term: String, config: LLMConfig) {
        stop()
        generation += 1
        let token = generation

        self.term = term
        self.config = config
        input = ""
        messages = []
        errorText = nil
        isStreaming = true

        history = [
            ChatMessage(.system, PromptBuilder.explainSystemPrompt(targetLanguage: config.targetLanguage)),
            ChatMessage(.user, PromptBuilder.explainFirstMessage(selection: String(term.prefix(4000))))
        ]

        let placeholder = Message(role: .assistant, content: "", isStreaming: true)
        messages = [placeholder]
        streamAnswer(for: placeholder.id, token: token)
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming, let config else { return }

        generation += 1
        let token = generation
        input = ""
        errorText = nil

        let question = Message(role: .user, content: text)
        messages.append(question)
        history.append(ChatMessage(.user, text))

        let placeholder = Message(role: .assistant, content: "", isStreaming: true)
        messages.append(placeholder)
        isStreaming = true
        streamAnswer(for: placeholder.id, token: token, config: config)
    }

    /// 失败后重试：丢掉空的回答占位，用现有对话历史再请求一次
    func retry() {
        guard !isStreaming, let config else { return }
        errorText = nil
        generation += 1
        let token = generation

        // 丢掉上次失败/半截的回答，再用现有对话历史重新请求
        if let last = messages.last, last.role == .assistant {
            messages.removeLast()
        }
        let placeholder = Message(role: .assistant, content: "", isStreaming: true)
        messages.append(placeholder)
        isStreaming = true
        streamAnswer(for: placeholder.id, token: token, config: config)
    }

    private func streamAnswer(for messageID: String, token: Int, config: LLMConfig? = nil) {
        guard let config = config ?? self.config else { return }
        let requestMessages = history
        let term = self.term

        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client.streamChat(messages: requestMessages, config: config) { [weak self] delta in
                    guard let self, self.generation == token else { return }
                    guard let index = self.messages.firstIndex(where: { $0.id == messageID }) else { return }
                    self.messages[index].content += delta
                }
                guard !Task.isCancelled, self.generation == token else { return }
                self.finishAnswer(messageID: messageID, term: term)
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                self.failAnswer(messageID: messageID, error: error)
            }
        }
    }

    private func finishAnswer(messageID: String, term: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].isStreaming = false
        let answer = messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines)
        isStreaming = false

        guard !answer.isEmpty else {
            messages.remove(at: index)
            errorText = "模型没有返回内容，可以重试一次。"
            return
        }

        history.append(ChatMessage(.assistant, answer))
        DebugLog.write("解释完成：\(term.prefix(20)) \(answer.count) 字符")
    }

    private func failAnswer(messageID: String, error: Error) {
        isStreaming = false
        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index].isStreaming = false
            if messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages.remove(at: index)
            }
        }
        errorText = error.localizedDescription
        DebugLog.write("解释失败：\(error.localizedDescription)")
    }

    func stop() {
        task?.cancel()
        task = nil
        generation += 1
        isStreaming = false
        for index in messages.indices {
            messages[index].isStreaming = false
        }
    }

    func reset() {
        stop()
        term = ""
        messages = []
        input = ""
        errorText = nil
        history = []
        config = nil
    }

    // MARK: - 收藏

    /// 这条回答对应的提问：往前找最近一条用户消息，第一轮则是「解释选中内容」
    func question(for messageID: String) -> String {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            return defaultQuestion
        }
        for candidate in messages[..<index].reversed() where candidate.role == .user {
            return candidate.content
        }
        return defaultQuestion
    }

    private var defaultQuestion: String {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "解释选中内容" }
        let preview = trimmed.count > 80 ? String(trimmed.prefix(80)) + "…" : trimmed
        return "解释「\(preview)」"
    }

    func toggleFavorite(messageID: String, favorites: ExplainFavorites) {
        guard messages.contains(where: { $0.id == messageID && $0.role == .assistant }) else { return }
        if favorites.contains(messageID: messageID) {
            favorites.remove(messageID: messageID)
            return
        }
        guard let message = messages.first(where: { $0.id == messageID }) else { return }
        favorites.add(
            messageID: messageID,
            term: term,
            question: question(for: messageID),
            answer: message.content
        )
    }

    func copy(messageID: String) {
        guard let message = messages.first(where: { $0.id == messageID }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
    }
}