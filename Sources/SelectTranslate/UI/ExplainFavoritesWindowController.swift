import AppKit
import Combine

/// 解释收藏夹：左侧列表，右侧显示完整问答
@MainActor
final class ExplainFavoritesWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private var window: NSWindow?
    private let favorites = ExplainFavorites.shared
    private let table = NSTableView()
    private let split = NSSplitView()
    private let search = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let detail = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 400))
    private let emptyLabel = NSTextField(wrappingLabelWithString:
        "还没有收藏的解释。\n解释浮窗里每条回答下面有「收藏」，点一下就会出现在这里。")
    private var rows: [ExplainFavorite] = []
    private var cancellable: AnyCancellable?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    func show() {
        if window == nil { buildWindow() }
        reload()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.contentView?.layoutSubtreeIfNeeded()
        split.setPosition(432, ofDividerAt: 0)
        layoutDetail()
    }

    /// 调试用：把窗口内容离屏渲染成 PNG
    func snapshot(to path: String) {
        guard let view = window?.contentView else {
            DebugLog.write("favorites snapshot: no window")
            return
        }
        view.layoutSubtreeIfNeeded()
        split.setPosition(432, ofDividerAt: 0)
        layoutDetail()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            DebugLog.write("favorites snapshot: no bitmap rep")
            return
        }
        // cacheDisplay 不会画窗口背景，先铺一层底色，否则未绘制的区域在 PNG 里是黑的
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: view.bounds.size).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        DebugLog.write("favorites snapshot written \(data.count) bytes")
    }

    // MARK: - 界面

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 540),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "解释收藏"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 680, height: 400)
        window.delegate = self
        window.center()
        window.contentView = buildContentView()
        self.window = window

        cancellable = favorites.$entries.sink { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    private func buildContentView() -> NSView {
        search.placeholderString = "搜索术语、提问或回答"
        search.delegate = self
        search.font = .systemFont(ofSize: 12)
        search.setContentHuggingPriority(.defaultLow, for: .horizontal)

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor

        let header = NSStackView(views: [search, countLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 30
        table.allowsMultipleSelection = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(copySelected)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        table.addTableColumn(column(id: "term", title: "术语", width: 138))
        table.addTableColumn(column(id: "question", title: "提问", width: 150))
        table.addTableColumn(column(id: "date", title: "收藏时间", width: 120))

        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.autohidesScrollers = true
        tableScroll.borderType = .bezelBorder

        detail.isEditable = false
        detail.isSelectable = true
        detail.drawsBackground = false
        detail.font = .systemFont(ofSize: 12.5)
        detail.textContainerInset = NSSize(width: 12, height: 12)
        detail.isHorizontallyResizable = false
        detail.isVerticallyResizable = true
        detail.textContainer?.widthTracksTextView = true
        detail.textContainer?.containerSize = NSSize(width: 420, height: CGFloat.greatestFiniteMagnitude)
        detail.minSize = .zero
        detail.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        detail.autoresizingMask = [.width]

        let detailScroll = NSScrollView()
        detailScroll.documentView = detail
        detailScroll.hasVerticalScroller = true
        detailScroll.autohidesScrollers = true
        detailScroll.borderType = .bezelBorder

        let split = self.split
        split.isVertical = true
        split.dividerStyle = .thin
        split.frame = NSRect(x: 0, y: 0, width: 824, height: 430)
        tableScroll.frame = NSRect(x: 0, y: 0, width: 432, height: 430)
        detailScroll.frame = NSRect(x: 433, y: 0, width: 391, height: 430)
        split.addArrangedSubview(tableScroll)
        split.addArrangedSubview(detailScroll)
        tableScroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        detailScroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center

        let deleteButton = NSButton(title: "删除选中", target: self, action: #selector(deleteSelected))
        deleteButton.bezelStyle = .rounded
        let copyButton = NSButton(title: "复制", target: self, action: #selector(copySelected))
        copyButton.bezelStyle = .rounded
        let clearButton = NSButton(title: "清空全部", target: self, action: #selector(clearAll))
        clearButton.bezelStyle = .rounded
        let closeButton = NSButton(title: "关闭", target: self, action: #selector(closeWindow))
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\r"

        let footer = NSStackView(views: [deleteButton, copyButton, clearButton, NSView(), closeButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8

        let stack = NSStackView(views: [header, split, emptyLabel, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            split.widthAnchor.constraint(equalTo: stack.widthAnchor),
            emptyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            split.heightAnchor.constraint(greaterThanOrEqualToConstant: 240)
        ])
        return container
    }

    private func column(id: String, title: String, width: CGFloat) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.minWidth = 70
        return column
    }

    // MARK: - 数据

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, row < rows.count else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("cell-" + tableColumn.identifier.rawValue)
        let cell: NSTextField
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            cell = reused
        } else {
            cell = NSTextField(labelWithString: "")
            cell.identifier = identifier
            cell.lineBreakMode = .byTruncatingTail
            cell.font = .systemFont(ofSize: 12)
        }

        let entry = rows[row]
        switch tableColumn.identifier.rawValue {
        case "term":
            cell.stringValue = entry.term.replacingOccurrences(of: "\n", with: " ")
            cell.font = .systemFont(ofSize: 12, weight: .medium)
            cell.textColor = .labelColor
        case "question":
            cell.stringValue = entry.question.replacingOccurrences(of: "\n", with: " ")
            cell.font = .systemFont(ofSize: 11)
            cell.textColor = .secondaryLabelColor
        case "date":
            cell.stringValue = Self.dateFormatter.string(from: entry.createdAt)
            cell.font = .systemFont(ofSize: 10)
            cell.textColor = .secondaryLabelColor
        default:
            cell.stringValue = ""
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        showDetail()
    }

    private func reload() {
        let previousID = selectedEntry()?.id
        let keyword = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if keyword.isEmpty {
            rows = favorites.entries
        } else {
            rows = favorites.entries.filter {
                $0.term.lowercased().contains(keyword)
                    || $0.question.lowercased().contains(keyword)
                    || $0.answer.lowercased().contains(keyword)
            }
        }
        table.reloadData()
        countLabel.stringValue = keyword.isEmpty
            ? "共 \(rows.count) 条"
            : "找到 \(rows.count) 条"
        emptyLabel.isHidden = !rows.isEmpty

        if let previousID, let index = rows.firstIndex(where: { $0.id == previousID }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if !rows.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        showDetail()
    }

    private func selectedEntry() -> ExplainFavorite? {
        let index = table.selectedRow
        guard index >= 0, index < rows.count else { return nil }
        return rows[index]
    }

    /// NSTextView 作为 NSScrollView 的 documentView 时不会自动跟随宽度，
    /// 这里显式把它拉到可视宽度，否则长回答会被右边裁掉。
    private func layoutDetail() {
        guard let scroll = detail.enclosingScrollView else { return }
        let size = scroll.contentSize
        guard size.width > 20 else { return }
        let height = max(detail.frame.height, size.height)
        detail.frame = NSRect(x: 0, y: 0, width: size.width, height: height)
        detail.textContainer?.containerSize = NSSize(width: size.width, height: CGFloat.greatestFiniteMagnitude)
    }

    func windowDidResize(_ notification: Notification) {
        layoutDetail()
    }

    private func showDetail() {
        guard let entry = selectedEntry() else {
            detail.textStorage?.setAttributedString(NSAttributedString(
                string: "选择左侧一条收藏查看完整内容。",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]
            ))
            return
        }

        let text = NSMutableAttributedString()
        text.append(NSAttributedString(
            string: entry.term,
            attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        ))
        text.append(NSAttributedString(
            string: "\n收藏于 " + Self.dateFormatter.string(from: entry.createdAt),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
        ))
        text.append(NSAttributedString(
            string: "\n\n提问\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        ))
        text.append(NSAttributedString(
            string: entry.question + "\n\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        ))
        text.append(NSAttributedString(
            string: "回答\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        ))
        text.append(NSAttributedString(
            string: entry.answer,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12.5),
                .foregroundColor: NSColor.labelColor
            ]
        ))
        detail.textStorage?.setAttributedString(text)
    }

    // MARK: - 交互

    func controlTextDidChange(_ obj: Notification) {
        reload()
    }

    @objc private func deleteSelected() {
        let selected = table.selectedRowIndexes
        guard !selected.isEmpty else {
            NSSound.beep()
            return
        }
        for index in selected {
            guard index < rows.count else { continue }
            favorites.remove(id: rows[index].id)
        }
    }

    @objc private func copySelected() {
        let index = table.selectedRow >= 0 ? table.selectedRow : (table.clickedRow >= 0 ? table.clickedRow : -1)
        guard index >= 0, index < rows.count else {
            NSSound.beep()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rows[index].plainText, forType: .string)
    }

    @objc private func clearAll() {
        guard !favorites.entries.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "清空解释收藏？"
        alert.informativeText = "共 \(favorites.entries.count) 条，清空后无法恢复。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            favorites.clear()
        }
    }

    @objc private func closeWindow() {
        window?.close()
    }
}