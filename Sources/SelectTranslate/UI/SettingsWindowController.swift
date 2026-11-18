import AppKit

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let baseURLField = NSTextField()
    private let modelField = NSTextField()
    private let modelsPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fetchModelsButton = NSButton(title: "拉取模型", target: nil, action: nil)
    private var fetchTask: Task<Void, Never>?
    private let apiKeyField = NSSecureTextField()
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let permissionLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let bubbleCheckbox = NSButton(checkboxWithTitle: "拖选文字后在鼠标旁显示翻译小按钮", target: nil, action: nil)
    private let vocabCheckbox = NSButton(checkboxWithTitle: "翻译后列出难词（雅思 / 托福 / 学术词汇）", target: nil, action: nil)

    private let presets: [(name: String, baseURL: String, model: String)] = [
        ("自定义", "", ""),
        ("DeepSeek", "https://api.deepseek.com/v1", "deepseek-chat"),
        ("OpenAI", "https://api.openai.com/v1", "gpt-4o-mini"),
        ("Kimi", "https://api.moonshot.cn/v1", "moonshot-v1-8k"),
        ("智谱 GLM", "https://open.bigmodel.cn/api/paas/v4", "glm-4-flash"),
        ("OpenRouter", "https://openrouter.ai/api/v1", "openai/gpt-4o-mini"),
        ("本地 Ollama", "http://127.0.0.1:11434/v1", "qwen2.5:7b")
    ]

    private let languages = ["简体中文", "繁體中文", "English", "日本語", "한국어"]

    func show() {
        if window == nil { buildWindow() }
        loadValues()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "划词翻译设置"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = buildContentView()
        self.window = window
    }

    private func buildContentView() -> NSView {
        presetPopup.addItems(withTitles: presets.map(\.name))
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)

        baseURLField.placeholderString = "https://api.deepseek.com/v1"
        modelField.placeholderString = "deepseek-chat"
        apiKeyField.placeholderString = "sk-..."
        for field in [baseURLField, modelField, apiKeyField] as [NSTextField] {
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        }

        languagePopup.addItems(withTitles: languages)

        fetchModelsButton.bezelStyle = .rounded
        fetchModelsButton.controlSize = .small
        fetchModelsButton.target = self
        fetchModelsButton.action = #selector(fetchModels)
        fetchModelsButton.setContentHuggingPriority(.required, for: .horizontal)
        fetchModelsButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let modelInputRow = NSStackView(views: [modelField, fetchModelsButton])
        modelInputRow.orientation = .horizontal
        modelInputRow.alignment = .centerY
        modelInputRow.spacing = 8

        modelsPopup.addItem(withTitle: "尚未拉取")
        modelsPopup.isEnabled = false
        modelsPopup.target = self
        modelsPopup.action = #selector(modelPicked)
        modelsPopup.toolTip = "填好 Base URL 和 API Key 后点「拉取模型」"

        let grid = NSGridView(views: [
            [caption("Base URL"), baseURLField],
            [caption("模型"), modelInputRow],
            [caption("可用模型"), modelsPopup],
            [caption("API Key"), apiKeyField],
            [caption("目标语言"), languagePopup]
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 68

        let presetRow = NSStackView(views: [caption("快速填充"), presetPopup])
        presetRow.orientation = .horizontal
        presetRow.spacing = 12

        let hint = NSTextField(wrappingLabelWithString:
            "兼容 OpenAI 协议的模型都能用（DeepSeek / OpenAI / Kimi / GLM / OpenRouter / 本地 Ollama）。填好 Base URL 和 API Key 后点「拉取模型」，可直接读取当前 Key 可用的模型；API Key 只保存在本机钥匙串，不会写入配置文件或日志。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        permissionLabel.font = .systemFont(ofSize: 11)

        let permissionButton = NSButton(title: "打开系统设置", target: self, action: #selector(openPermissions))
        permissionButton.bezelStyle = .rounded
        let permissionRow = NSStackView(views: [permissionLabel, NSView(), permissionButton])
        permissionRow.orientation = .horizontal
        permissionRow.spacing = 10

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let saveButton = NSButton(title: "保存", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        let buttonRow = NSStackView(views: [statusLabel, NSView(), saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let stack = NSStackView(views: [
            presetRow, grid, hint, bubbleCheckbox, vocabCheckbox,
            separator(), permissionRow, separator(), buttonRow
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20),
            baseURLField.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            modelField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            modelsPopup.widthAnchor.constraint(equalToConstant: 380),
            apiKeyField.widthAnchor.constraint(greaterThanOrEqualToConstant: 320)
        ])
        return container
    }

    private func caption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.font = .systemFont(ofSize: 12)
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func loadValues() {
        fetchTask?.cancel()
        fetchTask = nil
        endFetch()
        modelsPopup.removeAllItems()
        modelsPopup.addItem(withTitle: "尚未拉取")
        modelsPopup.isEnabled = false

        let defaults = UserDefaults.standard
        baseURLField.stringValue = defaults.string(forKey: "baseURL") ?? LLMConfig.defaultBaseURL
        modelField.stringValue = defaults.string(forKey: "model") ?? LLMConfig.defaultModel
        apiKeyField.stringValue = Keychain.load() ?? ""
        let language = defaults.string(forKey: "targetLanguage") ?? LLMConfig.defaultTargetLanguage
        languagePopup.selectItem(withTitle: language)

        let index = presets.firstIndex { $0.baseURL == baseURLField.stringValue && $0.model == modelField.stringValue }
        presetPopup.selectItem(at: index ?? 0)

        let showBubble = defaults.object(forKey: "showBubbleOnSelection") as? Bool ?? true
        bubbleCheckbox.state = showBubble ? .on : .off
        let showVocabulary = defaults.object(forKey: "showVocabulary") as? Bool ?? true
        vocabCheckbox.state = showVocabulary ? .on : .off

        updatePermissionLabel()
        setStatus("", isError: false)
    }

    private func updatePermissionLabel() {
        if SelectionReader.isTrusted {
            permissionLabel.stringValue = "辅助功能：已授权"
            permissionLabel.textColor = .secondaryLabelColor
        } else {
            permissionLabel.stringValue = "辅助功能：未授权（无法读取其他 App 的选中文字）"
            permissionLabel.textColor = .systemRed
        }
    }

    // MARK: - 拉取模型

    @objc private func fetchModels() {
        let base = baseURLField.stringValue.trimmed
        let key = apiKeyField.stringValue.trimmed

        guard !base.isEmpty else {
            setStatus("先填 Base URL", isError: true)
            return
        }
        guard ModelCatalog.isValidBaseURL(base) else {
            setStatus("Base URL 需要以 http:// 或 https:// 开头", isError: true)
            return
        }

        fetchTask?.cancel()
        fetchModelsButton.isEnabled = false
        fetchModelsButton.title = "拉取中…"
        modelsPopup.isEnabled = false
        setStatus("正在拉取 \(base) 的模型列表…", isError: false)

        fetchTask = Task { [weak self] in
            do {
                let models = try await ModelCatalog.fetchModels(baseURL: base, apiKey: key)
                guard let self, !Task.isCancelled else { return }
                self.apply(models)
            } catch is CancellationError {
                // 被新的请求或关窗打断，界面由新请求接管
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.endFetch()
                self.setStatus(error.localizedDescription, isError: true)
            }
        }
    }

    private func apply(_ models: [String]) {
        endFetch()
        modelsPopup.removeAllItems()

        guard !models.isEmpty else {
            modelsPopup.addItem(withTitle: "没有返回模型")
            modelsPopup.isEnabled = false
            setStatus("接口没有返回任何模型，检查一下 Base URL 和 Key 的权限。", isError: true)
            return
        }

        modelsPopup.addItem(withTitle: "选择模型…")
        modelsPopup.addItems(withTitles: models)
        modelsPopup.isEnabled = true
        if let index = models.firstIndex(of: modelField.stringValue.trimmed) {
            modelsPopup.selectItem(at: index + 1)
        } else {
            modelsPopup.selectItem(at: 0)
        }
        setStatus("共 \(models.count) 个可用模型，从下拉框选一个。", isError: false)
    }

    private func endFetch() {
        fetchModelsButton.isEnabled = true
        fetchModelsButton.title = "拉取模型"
    }

    private func setStatus(_ text: String, isError: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
        statusLabel.toolTip = text
    }

    @objc private func modelPicked() {
        let index = modelsPopup.indexOfSelectedItem
        guard index > 0, let title = modelsPopup.item(at: index)?.title else { return }
        modelField.stringValue = title
        setStatus("已选择 \(title)，点「保存」后生效。", isError: false)
    }

    @objc private func presetChanged() {
        let index = presetPopup.indexOfSelectedItem
        guard presets.indices.contains(index), !presets[index].baseURL.isEmpty else { return }
        baseURLField.stringValue = presets[index].baseURL
        modelField.stringValue = presets[index].model
        modelsPopup.removeAllItems()
        modelsPopup.addItem(withTitle: "尚未拉取")
        modelsPopup.isEnabled = false
    }

    @objc private func openPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func save() {
        let defaults = UserDefaults.standard
        defaults.set(baseURLField.stringValue.trimmed, forKey: "baseURL")
        defaults.set(modelField.stringValue.trimmed, forKey: "model")
        defaults.set(languagePopup.titleOfSelectedItem ?? LLMConfig.defaultTargetLanguage, forKey: "targetLanguage")
        defaults.set(bubbleCheckbox.state == .on, forKey: "showBubbleOnSelection")
        defaults.set(vocabCheckbox.state == .on, forKey: "showVocabulary")
        Keychain.save(apiKeyField.stringValue)
        setStatus("已保存", isError: false)
    }
}