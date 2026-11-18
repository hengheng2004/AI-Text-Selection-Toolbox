import AppKit

/// 拖选文字后在鼠标旁浮出的小按钮组，点一下才真正翻译 / 解释（避免每次划词都消耗 token）
@MainActor
final class SelectionBubbleController {
    var onTranslate: ((String, NSPoint) -> Void)?
    var onExplain: ((String, NSPoint) -> Void)?

    private var panel: NSPanel?
    private var selectedText = ""

    var isVisible: Bool { panel?.isVisible == true }

    func contains(_ point: NSPoint) -> Bool {
        panel?.frame.contains(point) ?? false
    }

    func show(text: String, at point: NSPoint) {
        selectedText = text
        let panel = ensurePanel()
        position(panel, near: point)
        panel.orderFrontRegardless()
        DebugLog.write("气泡显示：\(text.count) 字符 @ \(point)")
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// 调试用：把气泡离屏渲染成 PNG
    func snapshot(to path: String) {
        guard let view = panel?.contentView else {
            DebugLog.write("bubble snapshot: no panel")
            return
        }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        DebugLog.write("bubble snapshot written \(data.count) bytes")
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let buttonSize = NSSize(width: 40, height: 40)
        let panelSize = NSSize(width: buttonSize.width * 2 + 8, height: buttonSize.height + 4)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow

        let translate = makeButton(
            symbol: "text.bubble.fill",
            tooltip: "翻译选中文字",
            action: #selector(tappedTranslate)
        )
        let explain = makeButton(
            symbol: "questionmark.bubble.fill",
            tooltip: "让 AI 解释选中内容",
            action: #selector(tappedExplain)
        )

        let stack = NSStackView(views: [translate, explain])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        panel.contentView = container

        self.panel = panel
        return panel
    }

    private func makeButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        button.bezelStyle = .circular
        button.isBordered = true
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.image?.isTemplate = true
        button.contentTintColor = .controlAccentColor
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40)
        ])
        return button
    }

    private func position(_ panel: NSPanel, near point: NSPoint) {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let size = panel.frame.size
        var x = point.x + 10
        var y = point.y - size.height - 8
        if x + size.width > visible.maxX - 6 { x = visible.maxX - size.width - 6 }
        if y < visible.minY + 6 { y = point.y + 18 }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func tappedTranslate() {
        fire(onTranslate)
    }

    @objc private func tappedExplain() {
        fire(onExplain)
    }

    private func fire(_ callback: ((String, NSPoint) -> Void)?) {
        let text = selectedText
        let point = NSEvent.mouseLocation
        hide()
        guard !text.isEmpty else { return }
        callback?(text, point)
    }
}