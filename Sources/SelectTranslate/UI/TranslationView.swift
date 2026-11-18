import SwiftUI

struct TranslationView: View {
    @ObservedObject var model: TranslationViewModel
    @ObservedObject var panel: PanelState
    @ObservedObject var book: VocabBook
    var onClose: () -> Void
    var onCopy: () -> Void
    var onCopyWord: (String) -> Void = { _ in }
    var onTogglePin: () -> Void = {}
    var onRetranslate: () -> Void = {}
    var onDragChanged: (CGSize) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider().opacity(0.6)

            if model.isWordMode {
                dictionaryArea
            } else {
                translationArea

                if showsVocabulary {
                    Divider().opacity(0.6)
                    vocabularyArea
                }
            }

            Divider().opacity(0.6)
            originalArea
            footer
        }
        .padding(14)
        .frame(width: 440, height: 480, alignment: .topLeading)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private var showsVocabulary: Bool {
        switch model.vocabState {
        case .idle: return false
        default: return true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Image(systemName: model.isWordMode ? "book" : "character.book.closed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(model.isWordMode ? "词典" : "翻译")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in onDragChanged(value.translation) }
                    .onEnded { _ in onDragEnded() }
            )
            .help("按住拖动浮窗")

            Spacer()
            if model.isLoading {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }
            Button(action: onRetranslate) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(model.original.isEmpty)
            .help("忽略缓存，重新翻译")

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .help("复制译文")

            Button(action: onTogglePin) {
                Image(systemName: panel.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(panel.isPinned ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.plain)
            .help(panel.isPinned ? "取消固定（不再悬浮在桌面上）" : "固定在桌面，点击别处也不收起")

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("关闭（Esc）")
        }
        .font(.system(size: 12))
    }

    // MARK: - 词典模式（单个单词）

    private var dictionaryArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let entry = model.dictionary {
                    dictionaryHeadword(entry)
                    ForEach(Array(entry.senses.enumerated()), id: \.offset) { index, sense in
                        dictionarySense(index: index + 1, sense: sense)
                    }
                    if let synonyms = entry.synonyms, !synonyms.isEmpty {
                        synonymsRow(synonyms)
                    }
                    if let note = entry.note, !note.isEmpty {
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text(note)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else if model.dictState == .failed {
                    Text(failureText)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                        Text("查询中…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func dictionaryHeadword(_ entry: DictionaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(entry.word)
                    .font(.system(size: 22, weight: .semibold))
                    .textSelection(.enabled)
                if let tag = entry.levelTag {
                    levelBadge(tag)
                }
                Spacer(minLength: 0)
                dictionaryToggle(entry)
            }
            if let phonetic = entry.phonetic, !phonetic.isEmpty {
                Text(phonetic)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 2)
    }

    private func dictionaryToggle(_ entry: DictionaryEntry) -> some View {
        let added = book.contains(entry.word)
        return Button {
            if added {
                book.remove(word: entry.word)
            } else {
                book.add(entry, context: nil)
            }
        } label: {
            Label(added ? "已收录" : "加入生词本", systemImage: added ? "checkmark.circle.fill" : "plus.circle")
                .font(.system(size: 10))
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.plain)
        .foregroundStyle(added ? Color.accentColor : Color.secondary)
        .help(added ? "已在生词本，点击移除" : "加入生词本")
    }

    private func dictionarySense(index: Int, sense: DictionarySense) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(index)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10, alignment: .trailing)
                if let pos = sense.pos, !pos.isEmpty {
                    Text(pos)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.secondary)
                }
                Text(sense.meaning)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if let example = sense.example, !example.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    Text(example)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if let translation = sense.exampleTranslation, !translation.isEmpty {
                        Text(translation)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 16)
            }
        }
    }

    private func synonymsRow(_ synonyms: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("近义词")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 52), spacing: 6)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(synonyms, id: \.self) { word in
                    Text(word)
                        .font(.system(size: 10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .contentShape(Rectangle())
                        .onTapGesture { onCopyWord(word) }
                        .help("点击复制 \(word)")
                }
            }
        }
    }

    private var failureText: String {
        if case .failed(let message) = model.status { return message }
        return "查询失败"
    }

    private var translationArea: some View {
        ScrollView {
            Text(displayTranslation)
                .font(.system(size: 14))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var displayTranslation: String {
        if !model.translation.isEmpty { return model.translation }
        switch model.status {
        case .loading: return "翻译中…"
        case .failed(let message): return message
        default: return ""
        }
    }

    // MARK: - 生词

    private var vocabularyArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("生词")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if model.vocabState == .loading {
                    ProgressView().controlSize(.small).scaleEffect(0.6)
                } else if model.vocabState == .done, !model.vocabulary.isEmpty {
                    Text("\(model.vocabulary.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if !model.vocabulary.isEmpty {
                    Text("点击单词复制")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.vocabState == .failed {
            Text("生词获取失败")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        } else if model.vocabulary.isEmpty {
            Text(model.vocabState == .loading ? "正在挑生词…" : "这段没有需要特别记忆的难词")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(model.vocabulary) { item in
                        vocabRow(item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 4)
            }
            .frame(maxHeight: 172)
        }
    }

    private func vocabRow(_ item: VocabWord) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.word)
                        .font(.system(size: 12.5, weight: .semibold))
                    if let phonetic = item.phonetic, !phonetic.isEmpty {
                        Text(phonetic)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if let tag = item.levelTag {
                        levelBadge(tag)
                    }
                    Spacer(minLength: 0)
                }
                Text(detail(item))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
            .onTapGesture { onCopyWord(item.word) }
            .help("点击复制 \(item.word)")

            vocabToggle(item)
        }
    }

    private func vocabToggle(_ item: VocabWord) -> some View {
        let added = book.contains(item.word)
        return Button {
            if added {
                book.remove(word: item.word)
            } else {
                book.add(item, context: model.original)
            }
        } label: {
            Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(added ? Color.accentColor : Color.secondary)
        .help(added ? "已在生词本，点击移除" : "加入生词本")
    }

    private func detail(_ item: VocabWord) -> String {
        if let pos = item.pos, !pos.isEmpty {
            return "\(pos) \(item.meaning)"
        }
        return item.meaning
    }

    private func levelBadge(_ tag: String) -> some View {
        let color: Color
        switch tag {
        case "雅思": color = .orange
        case "托福": color = .blue
        case "学术": color = .purple
        default: color = .secondary
        }
        return Text(tag)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - 原文与状态

    private var originalArea: some View {
        Text(model.original)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(statusText)
                .font(.system(size: 10))
                .foregroundStyle(model.isFailed ? Color.red : Color.secondary)
            if model.isFromCache {
                Text("缓存")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if panel.isPinned {
                Label("已固定", systemImage: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Text(panel.isPinned ? "Esc 关闭" : "⌥D 再次翻译 · Esc 关闭")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var statusText: String {
        if model.isWordMode {
            switch model.dictState {
            case .loading: return "查询中"
            case .done: return "词典"
            case .failed: return "失败"
            case .idle: return ""
            }
        }
        switch model.status {
        case .loading: return "请求中"
        case .streaming: return "生成中…"
        case .done: return "完成"
        case .failed: return "失败"
        case .idle: return ""
        }
    }
}

private extension TranslationViewModel {
    var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }
}