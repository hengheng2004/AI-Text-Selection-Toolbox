import AppKit
import SwiftUI

final class ExplainPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

/// 解释浮窗：选中文字后打开，做临时多轮问答
@MainActor
final class ExplainPanelController {
    private let model = ExplainViewModel()
    private let state = PanelState(key: "explainPanelPinned")
    private let favorites = ExplainFavorites.shared
    private var panel: ExplainPanel?
    private var dragBaseOrigin: NSPoint?
    private var dragStartMouse: NSPoint?
    private var escMonitor: Any?

    func show(term: String, config: LLMConfig) {
        DebugLog.write("explain show(), termLen=\(term.count)")
        let panel = ensurePanel()
        model.start(term: term, config: config)
        applyPinState()
        position(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        installEscMonitorIfNeeded()
        DebugLog.write("explain panel ordered front, frame=\(panel.frame)")
    }

    func hide() {
        model.stop()
        panel?.orderOut(nil)
    }

    /// TextField 获得焦点时 Esc 会先进入 field editor，
    /// 用本地事件监听保证任何情况下 Esc 都能关掉浮窗。
    private func installEscMonitorIfNeeded() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel,
                  panel.isVisible, event.window === panel, event.keyCode == 53 else {
                return event
            }
            self.hide()
            return nil
        }
    }

    var isPinned: Bool { state.isPinned }

    var isVisible: Bool { panel?.isVisible ?? false }

    func contains(_ point: NSPoint) -> Bool {
        panel?.frame.contains(point) ?? false
    }

    func togglePin() {
        state.togglePin()
        applyPinState()
    }

    private func applyPinState() {
        guard let panel else { return }
        panel.level = .floating
        panel.collectionBehavior = state.isPinned
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            : [.canJoinAllSpaces, .fullScreenAuxiliary]
        if state.isPinned, !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func dragPanel(by translation: CGSize) {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragBaseOrigin == nil {
            dragBaseOrigin = panel.frame.origin
            dragStartMouse = NSPoint(
                x: mouse.x - translation.width,
                y: mouse.y + translation.height
            )
        }
        guard let base = dragBaseOrigin, let start = dragStartMouse else { return }
        panel.setFrameOrigin(NSPoint(
            x: base.x + (mouse.x - start.x),
            y: base.y + (mouse.y - start.y)
        ))
    }

    func endDrag() {
        dragBaseOrigin = nil
        dragStartMouse = nil
    }

    /// 调试用：向当前会话追加一轮追问
    func debugSendFollowup(_ text: String) {
        model.input = text
        model.send()
    }

    /// 调试用：收藏当前最后一条已完成的回答
    func debugFavoriteLastAnswer() {
        guard let message = model.messages.last(where: {
            $0.role == .assistant && !$0.isStreaming && !$0.content.isEmpty
        }) else {
            DebugLog.write("debug favorite: no finished answer")
            return
        }
        model.toggleFavorite(messageID: message.id, favorites: favorites)
        DebugLog.write("debug favorite toggled: \(message.id)")
    }

    /// 调试用：把浮窗内容离屏渲染成 PNG
    func snapshot(to path: String) {
        guard let view = panel?.contentView else {
            DebugLog.write("explain snapshot: no panel")
            return
        }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            DebugLog.write("explain snapshot: no bitmap rep")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        DebugLog.write("explain snapshot written \(data.count) bytes")
    }

    private func ensurePanel() -> ExplainPanel {
        if let panel { return panel }

        let panel = ExplainPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
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
        panel.onEscape = { [weak self] in self?.hide() }

        let root = ExplainView(
            model: model,
            panel: state,
            favorites: favorites,
            onClose: { [weak self] in self?.hide() },
            onTogglePin: { [weak self] in self?.togglePin() },
            onDragChanged: { [weak self] translation in
                self?.dragPanel(by: translation)
            },
            onDragEnded: { [weak self] in self?.endDrag() }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let size = panel.frame.size
        var x = mouse.x + 14
        var y = mouse.y - size.height - 14

        if x + size.width > visible.maxX - 8 { x = visible.maxX - size.width - 8 }
        if x < visible.minX + 8 { x = visible.minX + 8 }
        if y < visible.minY + 8 { y = mouse.y + 24 }
        if y + size.height > visible.maxY - 8 { y = visible.maxY - size.height - 8 }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}