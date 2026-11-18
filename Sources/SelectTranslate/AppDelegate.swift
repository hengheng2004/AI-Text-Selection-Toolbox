import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotKey = GlobalHotKey()
    private let explainHotKey = GlobalHotKey()
    private let panelController = TranslationPanelController()
    private let explainPanel = ExplainPanelController()
    private let settingsWindow = SettingsWindowController()
    private let bubble = SelectionBubbleController()
    private let mouseWatcher = MouseWatcher()
    private let statusWindow = StatusWindowController()
    private let vocabWindow = VocabBookWindowController()
    private let favoritesWindow = ExplainFavoritesWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        hotKey.register(id: 1, keyCode: UInt32(kVK_ANSI_D), carbonModifiers: UInt32(optionKey)) { [weak self] in
            self?.translateSelection()
        }
        explainHotKey.register(id: 2, keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(optionKey)) { [weak self] in
            self?.explainSelection()
        }
        statusWindow.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        DebugLog.write("launch: trusted=\(SelectionReader.isTrusted) path=\(Bundle.main.bundlePath)")

        _ = SelectionReader.ensureAccessibilityPermission(prompt: true)
        setupSelectionBubble()

        // 未授权或未配置 API 时，直接把状态窗口摆出来，避免“以为没打开”
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.statusWindow.showIfNeeded()
        }

        // 调试：`open --args --demo` 直接用示例文本打开翻译浮窗（不读选区）
        if CommandLine.arguments.contains("--demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.panelController.show(
                    text: "The quick brown fox jumps over the lazy dog. Machine translation quality depends on context.",
                    config: LLMConfig.load()
                )
            }
        }

        // 调试：`--word robust` 直接查一个单词（词典模式）
        if let index = CommandLine.arguments.firstIndex(of: "--word"),
           index + 1 < CommandLine.arguments.count {
            let word = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                DebugLog.write("forcing dictionary lookup: \(word)")
                self?.panelController.show(text: word, config: LLMConfig.load())
            }
        }

        // 调试：`--vocab` 直接打开生词本窗口
        if CommandLine.arguments.contains("--vocab") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                DebugLog.write("forcing vocab book window")
                self?.vocabWindow.show()
            }
        }

        // 调试：`--snapshot-vocab` 打开生词本窗口并离屏渲染 PNG 后退出
        if CommandLine.arguments.contains("--snapshot-vocab") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                self.vocabWindow.show()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.vocabWindow.snapshot(to: "/tmp/vocab-snapshot.png")
                    NSApp.terminate(nil)
                }
            }
        }

        // 调试：`--favorites` 直接打开解释收藏窗口
        if CommandLine.arguments.contains("--favorites") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                DebugLog.write("forcing explain favorites window")
                self?.favoritesWindow.show()
            }
        }

        // 调试：`--snapshot-favorites` 打开解释收藏并离屏渲染 PNG 后退出
        if CommandLine.arguments.contains("--snapshot-favorites") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                self.favoritesWindow.show()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.favoritesWindow.snapshot(to: "/tmp/favorites-snapshot.png")
                    NSApp.terminate(nil)
                }
            }
        }

        // 调试：`--explain [术语]` 直接用示例术语打开解释浮窗
        if CommandLine.arguments.contains("--explain") {
            let index = CommandLine.arguments.firstIndex(of: "--explain") ?? 0
            let next = index + 1
            let custom: String? = next < CommandLine.arguments.count
                && !CommandLine.arguments[next].hasPrefix("--")
                ? CommandLine.arguments[next]
                : nil
            let term = custom ?? "attention mechanism（注意力机制）"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                DebugLog.write("forcing explain panel: \(term)")
                self?.explainPanel.show(term: term, config: LLMConfig.load())
            }
        }

        // 调试：`--snapshot-explain` 打开解释浮窗，等首轮回答后离屏渲染 PNG 再退出
        if CommandLine.arguments.contains("--snapshot-explain") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                self.explainPanel.show(
                    term: "attention mechanism（注意力机制）",
                    config: LLMConfig.load()
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self.explainPanel.snapshot(to: "/tmp/explain-snapshot.png")
                    NSApp.terminate(nil)
                }
            }
        }

        // 调试：`--snapshot-explain-thread` 跑一轮追问 + 收藏，然后截图并打开收藏窗口
        if CommandLine.arguments.contains("--snapshot-explain-thread") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                self.explainPanel.show(
                    term: "attention mechanism（注意力机制）",
                    config: LLMConfig.load()
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    self.explainPanel.debugSendFollowup("能用一个具体的例子说明吗？")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                    self.explainPanel.debugFavoriteLastAnswer()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                    self.explainPanel.snapshot(to: "/tmp/explain-thread.png")
                    self.favoritesWindow.show()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    self.favoritesWindow.snapshot(to: "/tmp/favorites-snapshot.png")
                    NSApp.terminate(nil)
                }
            }
        }

        // 调试：`--snapshot-bubble` 在屏幕中间显示划词气泡并截图
        if CommandLine.arguments.contains("--snapshot-bubble") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                let screen = NSScreen.main?.visibleFrame ?? .zero
                let point = NSPoint(x: screen.midX, y: screen.midY)
                self.bubble.show(text: "attention mechanism", at: point)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.bubble.snapshot(to: "/tmp/bubble-snapshot.png")
                    NSApp.terminate(nil)
                }
            }
        }

        // 调试：`--status` 直接打开状态窗口
        if CommandLine.arguments.contains("--status") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                DebugLog.write("forcing status window")
                self?.statusWindow.show()
            }
        }

        // 调试：`--settings` 直接打开设置窗口
        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                DebugLog.write("forcing settings window")
                self?.settingsWindow.show()
            }
        }

        // 调试：`--snapshot` 离屏渲染浮窗为 PNG 后退出
        if CommandLine.arguments.contains("--snapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                DebugSnapshot.run()
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "划词翻译")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "翻译选中文字    ⌥D", action: #selector(translateSelection), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "解释选中文字    ⌥E", action: #selector(explainSelection), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "生词本…", action: #selector(showVocabBook), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "解释收藏…", action: #selector(showFavorites), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "状态与诊断…", action: #selector(showStatus), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "检查权限…", action: #selector(checkPermissions), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "清除翻译缓存", action: #selector(clearCache), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private func setupSelectionBubble() {
        bubble.onTranslate = { [weak self] text, _ in
            self?.translate(text: text)
        }
        bubble.onExplain = { [weak self] text, _ in
            self?.explain(text: text)
        }
        mouseWatcher.onMouseDown = { [weak self] point in
            guard let self else { return }
            if self.bubble.isVisible, !self.bubble.contains(point) {
                self.bubble.hide()
            }
            // 固定状态下点别处不收起
            if self.panelController.contains(point) == false,
               self.panelController.isVisible,
               !self.panelController.isPinned {
                self.panelController.hide()
            }
            if self.explainPanel.contains(point) == false,
               self.explainPanel.isVisible,
               !self.explainPanel.isPinned {
                self.explainPanel.hide()
            }
        }
        mouseWatcher.shouldIgnorePoint = { [weak self] point in
            guard let self else { return false }
            return self.bubble.contains(point)
                || self.panelController.contains(point)
                || self.explainPanel.contains(point)
        }
        mouseWatcher.onDragSelection = { [weak self] text, point in
            guard let self else { return }
            let enabled = UserDefaults.standard.object(forKey: "showBubbleOnSelection") as? Bool ?? true
            guard enabled else { return }
            self.bubble.show(text: text, at: point)
        }
        mouseWatcher.start()
    }

    @objc private func translateSelection() {
        guard ensureReady() else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = SelectionReader.readSelectedText()
            DispatchQueue.main.async {
                guard let self else { return }
                guard let text, !text.trimmed.isEmpty else {
                    self.showAlert(title: "没有读到选中文字", message: "先用鼠标选中一段文字，再按 ⌥D。")
                    return
                }
                self.translate(text: text.trimmed)
            }
        }
    }

    private func translate(text: String) {
        guard ensureReady() else { return }
        bubble.hide()
        panelController.show(text: text.trimmed, config: LLMConfig.load())
    }

    @objc private func explainSelection() {
        guard ensureReady() else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = SelectionReader.readSelectedText()
            DispatchQueue.main.async {
                guard let self else { return }
                guard let text, !text.trimmed.isEmpty else {
                    self.showAlert(title: "没有读到选中文字", message: "先用鼠标选中要解释的内容，再按 ⌥E。")
                    return
                }
                self.explain(text: text.trimmed)
            }
        }
    }

    private func explain(text: String) {
        guard ensureReady() else { return }
        bubble.hide()
        explainPanel.show(term: text.trimmed, config: LLMConfig.load())
    }

    /// 检查 API 配置与辅助功能权限，缺什么就提示什么
    private func ensureReady() -> Bool {
        guard LLMConfig.load().isConfigured else {
            let alert = NSAlert()
            alert.messageText = "还没有配置大模型 API"
            alert.informativeText = "填入 Base URL、模型和 API Key 之后就能用了。Key 只保存在本机钥匙串。"
            alert.addButton(withTitle: "去设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                settingsWindow.show()
            }
            return false
        }

        guard SelectionReader.isTrusted else {
            _ = SelectionReader.ensureAccessibilityPermission(prompt: true)
            showAlert(
                title: "需要辅助功能权限",
                message: "在「系统设置 → 隐私与安全性 → 辅助功能」里勾选「划词翻译」，然后重新启动应用。"
            )
            return false
        }
        return true
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func clearCache() {
        let count = TranslationCache.shared.count
        TranslationCache.shared.clear()
        showAlert(title: "缓存已清空", message: "共清除 \(count) 条翻译记录。")
    }

    @objc private func showStatus() {
        statusWindow.show()
    }

    @objc private func showVocabBook() {
        vocabWindow.show()
    }

    @objc private func showFavorites() {
        favoritesWindow.show()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func checkPermissions() {
        if SelectionReader.isTrusted {
            showAlert(title: "辅助功能权限正常", message: "已经可以读取其他 App 的选中文字。")
            return
        }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "还没有辅助功能权限"
        alert.informativeText = "在「系统设置 → 隐私与安全性 → 辅助功能」中勾选「划词翻译」，然后重新启动本应用。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}