import AppKit

@MainActor
final class StatusWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let trustLabel = NSTextField(labelWithString: "")
    private let configLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(wrappingLabelWithString: "")
    private var timer: Timer?
    private var lastLogged = ""

    var onOpenSettings: (() -> Void)?

    func showIfNeeded() {
        let configured = LLMConfig.load().isConfigured
        DebugLog.write("showIfNeeded: trusted=\(SelectionReader.isTrusted) configured=\(configured)")
        if !SelectionReader.isTrusted || !configured {
            show()
        }
    }

    func show() {
        DebugLog.write("StatusWindow.show() begin")
        if window == nil { buildWindow() }
        DebugLog.write("StatusWindow window ready: \(window != nil)")
        refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        startTimer()
        DebugLog.write("StatusWindow ordered front: visible=\(window?.isVisible ?? false) frame=\(String(describing: window?.frame))")
    }

    func refresh() {
        let trusted = SelectionReader.isTrusted
        trustLabel.stringValue = trusted ? "辅助功能：已授权" : "辅助功能：未授权"
        trustLabel.textColor = trusted ? .secondaryLabelColor : .systemRed

        let configured = LLMConfig.load().isConfigured
        configLabel.stringValue = configured ? "模型配置：已填写" : "模型配置：未填写"
        configLabel.textColor = configured ? .secondaryLabelColor : .systemOrange

        pathLabel.stringValue = "运行位置：" + Bundle.main.bundlePath

        let state = "trusted=\(trusted) configured=\(configured)"
        if state != lastLogged {
            lastLogged = state
            DebugLog.write("status: \(state) path=\(Bundle.main.bundlePath)")
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "划词翻译 · 状态"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let title = NSTextField(labelWithString: "划词翻译")
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        let subtitle = NSTextField(wrappingLabelWithString:
            "这是一个菜单栏应用，没有 Dock 图标。图标在屏幕右上角的菜单栏里（气泡形状），点它可以看到菜单。")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        trustLabel.font = .systemFont(ofSize: 13)
        configLabel.font = .systemFont(ofSize: 13)
        pathLabel.font = .systemFont(ofSize: 10)
        pathLabel.textColor = .tertiaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle

        let trustButton = NSButton(title: "打开辅助功能设置", target: self, action: #selector(openAccessibility))
        trustButton.bezelStyle = .rounded
        let configButton = NSButton(title: "去填 API", target: self, action: #selector(openSettings))
        configButton.bezelStyle = .rounded

        let trustRow = NSStackView(views: [trustLabel, NSView(), trustButton])
        trustRow.orientation = .horizontal
        trustRow.spacing = 10

        let configRow = NSStackView(views: [configLabel, NSView(), configButton])
        configRow.orientation = .horizontal
        configRow.spacing = 10

        hintLabel.stringValue = """
        勾选辅助功能后，这个窗口里的状态会自动变成「已授权」。
        如果一直不变：在辅助功能列表里选中旧的「划词翻译」按 − 删除，再点 + 重新添加下面这个路径的应用，然后重新勾选。
        """
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor

        let recheckButton = NSButton(title: "重新检查", target: self, action: #selector(recheck))
        recheckButton.bezelStyle = .rounded
        let copyButton = NSButton(title: "复制诊断信息", target: self, action: #selector(copyDiagnostics))
        copyButton.bezelStyle = .rounded
        let closeButton = NSButton(title: "关闭", target: self, action: #selector(closeWindow))
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\r"

        let buttonRow = NSStackView(views: [recheckButton, copyButton, NSView(), closeButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let stack = NSStackView(views: [
            title, subtitle, trustRow, configRow, pathLabel, hintLabel, buttonRow
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -18),
            trustRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            configRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pathLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hintLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        window.contentView = container
        self.window = window
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func recheck() {
        refresh()
        NSSound.beep()
    }

    @objc private func copyDiagnostics() {
        let text = """
        划词翻译诊断
        辅助功能：\(SelectionReader.isTrusted ? "已授权" : "未授权")
        模型配置：\(LLMConfig.load().isConfigured ? "已填写" : "未填写")
        路径：\(Bundle.main.bundlePath)
        版本：\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
        系统：\(ProcessInfo.processInfo.operatingSystemVersionString)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func closeWindow() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }
}