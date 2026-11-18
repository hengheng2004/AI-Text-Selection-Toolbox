import SwiftUI

struct ExplainView: View {
    @ObservedObject var model: ExplainViewModel
    @ObservedObject var panel: PanelState
    @ObservedObject var favorites: ExplainFavorites
    var onClose: () -> Void
    var onTogglePin: () -> Void
    var onDragChanged: (CGSize) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            termCard
            Divider().opacity(0.6)
            conversation
            if let error = model.errorText {
                errorRow(error)
            }
            Divider().opacity(0.6)
            inputRow
            footer
        }
        .padding(14)
        .frame(width: 460, height: 560, alignment: .topLeading)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Image(systemName: "questionmark.bubble")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("解释")
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

            if model.isStreaming {
                ProgressView().controlSize(.small).scaleEffect(0.65)
            }

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

    // MARK: - 选中内容

    private var termCard: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "text.quote")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("选中内容")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(model.term)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - 对话

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.messages) { message in
                        messageRow(message)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: model.messages.last?.content.count) { _, _ in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: model.messages.count) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ExplainViewModel.Message) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(message.content)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.85), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                if message.content.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).scaleEffect(0.65)
                        Text("正在解释…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(message.content)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !message.isStreaming, !message.content.isEmpty {
                    answerActions(message)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func answerActions(_ message: ExplainViewModel.Message) -> some View {
        let added = favorites.contains(messageID: message.id)
        return HStack(spacing: 10) {
            Button {
                model.toggleFavorite(messageID: message.id, favorites: favorites)
            } label: {
                Label(added ? "已收藏" : "收藏", systemImage: added ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(added ? Color.accentColor : Color.secondary)
            .help(added ? "已收藏，点击取消" : "收藏这一轮问答")

            Button {
                model.copy(messageID: message.id)
            } label: {
                Label("复制", systemImage: "doc.on.doc")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("复制这条回答")

            Spacer(minLength: 0)
        }
    }

    private func errorRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("重试") { model.retry() }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: - 输入

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 7) {
            TextField("继续追问…（⏎ 发送）", text: $model.input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1...4)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .onSubmit { model.send() }

            Button {
                model.send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.canSend ? Color.accentColor : Color.secondary.opacity(0.5))
            .disabled(!model.canSend)
            .help("发送（⏎）")
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(model.isStreaming ? "回答中…" : "临时对话 · 收藏后才会保存")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            if panel.isPinned {
                Label("已固定", systemImage: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Text("Esc 关闭")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}