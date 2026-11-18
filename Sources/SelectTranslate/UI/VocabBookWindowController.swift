import AppKit
import Combine

/// 生词本窗口：AppKit 实现（SwiftUI 宏在 Command Line Tools 下不可用）
@MainActor
final class VocabBookWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private var window: NSWindow?
    private let book = VocabBook.shared
    private let table = NSTableView()
    private let search = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(wrappingLabelWithString:
        "生词本还是空的。\n翻译时点生词右边的 + ，或查单词时点「加入生词本」，就会出现在这里。")
    private var rows: [VocabEntry] = []
    private var cancellable: AnyCancellable?

    func show() {
        if window == nil { buildWindow() }
        reload()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// 调试用：把窗口内容离屏渲染成 PNG
    func snapshot(to path: String) {
        guard let view = window?.contentView else {
            DebugLog.write("vocab snapshot: no window")
            return
        }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            DebugLog.write("vocab snapshot: no bitmap rep")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        DebugLog.write("vocab snapshot written \(data.count) bytes")
    }

    // MARK: - 界面

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "生词本"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 360)
        window.center()
        window.contentView = buildContentView()
        self.window = window

        cancellable = book.$entries.sink { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    private func buildContentView() -> NSView {
        search.placeholderString = "搜索单词或释义"
        search.delegate = self
        search.font = .systemFont(ofSize: 12)

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [search, countLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        search.setContentHuggingPriority(.defaultLow, for: .horizontal)

        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 30
        table.allowsMultipleSelection = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(copySelected)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        table.addTableColumn(column(id: "word", title: "单词", width: 150))
        table.addTableColumn(column(id: "phonetic", title: "音标", width: 130))
        table.addTableColumn(column(id: "meaning", title: "释义", width: 330))
        table.addTableColumn(column(id: "level", title: "标签", width: 80))

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

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

        let stack = NSStackView(views: [header, scroll, emptyLabel, footer])
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
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            emptyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])
        return container
    }

    private func column(id: String, title: String, width: CGFloat) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.minWidth = 60
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
        case "word":
            cell.stringValue = entry.word
            cell.font = .systemFont(ofSize: 12, weight: .medium)
            cell.textColor = .labelColor
        case "phonetic":
            cell.stringValue = entry.phonetic ?? ""
            cell.font = .systemFont(ofSize: 11)
            cell.textColor = .secondaryLabelColor
        case "meaning":
            let prefix = (entry.pos?.isEmpty == false) ? "\(entry.pos!) " : ""
            cell.stringValue = prefix + entry.meaning
            cell.font = .systemFont(ofSize: 12)
            cell.textColor = .labelColor
        case "level":
            cell.stringValue = entry.levelTag ?? ""
            cell.font = .systemFont(ofSize: 10)
            cell.textColor = .secondaryLabelColor
        default:
            cell.stringValue = ""
        }
        return cell
    }

    private func reload() {
        let keyword = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if keyword.isEmpty {
            rows = book.entries
        } else {
            rows = book.entries.filter {
                $0.word.lowercased().contains(keyword) || $0.meaning.lowercased().contains(keyword)
            }
        }
        table.reloadData()
        countLabel.stringValue = keyword.isEmpty
            ? "共 \(rows.count) 个词"
            : "找到 \(rows.count) 个词"
        emptyLabel.isHidden = !rows.isEmpty
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
            book.remove(id: rows[index].id)
        }
    }

    @objc private func copySelected() {
        let index = table.selectedRow >= 0 ? table.selectedRow : (table.clickedRow >= 0 ? table.clickedRow : -1)
        guard index >= 0, index < rows.count else {
            NSSound.beep()
            return
        }
        let entry = rows[index]
        var text = entry.word
        if let phonetic = entry.phonetic, !phonetic.isEmpty { text += "  \(phonetic)" }
        if let pos = entry.pos, !pos.isEmpty { text += "  \(pos)" }
        text += "  " + entry.meaning
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func clearAll() {
        guard !book.entries.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "清空生词本？"
        alert.informativeText = "共 \(book.entries.count) 个词，清空后无法恢复。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            book.clear()
        }
    }

    @objc private func closeWindow() {
        window?.close()
    }
}