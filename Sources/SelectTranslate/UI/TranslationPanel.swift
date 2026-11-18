import AppKit
import SwiftUI

final class TranslationPanel: NSPanel {
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
}

@MainActor
final class TranslationPanelController {
    private let model = TranslationViewModel()
    private let state = PanelState()
    private var panel: TranslationPanel?
    /// 拖动开始时的窗口原点与鼠标屏幕位置
    private var dragBaseOrigin: NSPoint?
    private var dragStartMouse: NSPoint?

    func show(text: String, config: LLMConfig) {
        DebugLog.write("show() called, textLen=\(text.count)")
        let panel = ensurePanel()
        model.start(text: text, config: config)
        applyPinState()
        position(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
        DebugLog.write("panel ordered front, frame=\(panel.frame), visible=\(panel.isVisible), alpha=\(panel.alphaValue)")
    }

    func hide() {
        model.stop()
        panel?.orderOut(nil)
    }

    /// 固定在桌面：不因为点击别处而自动收起，并跟随所有空间显示
    var isPinned: Bool {
        state.isPinned
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

    func contains(_ point: NSPoint) -> Bool {
        panel?.frame.contains(point) ?? false
    }

    /// 拖动浮窗标题区域：用鼠标在屏幕上的位移移动窗口，
    /// 避免窗口移动后 SwiftUI 局部坐标系跟着变化，导致拖动漂移。
    func dragPanel(by translation: CGSize) {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragBaseOrigin == nil {
            dragBaseOrigin = panel.frame.origin
            // 首次回调时窗口还没移动，用 translation 反推出按下时的鼠标位置
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

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    private func ensurePanel() -> TranslationPanel {
        if let panel { return panel }

        let panel = TranslationPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
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

        let root = TranslationView(
            model: model,
            panel: state,
            book: VocabBook.shared,
            onClose: { [weak self] in self?.hide() },
            onCopy: { [weak self] in self?.copyTranslation() },
            onCopyWord: { word in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(word, forType: .string)
            },
            onTogglePin: { [weak self] in self?.togglePin() },
            onRetranslate: { [weak self] in self?.model.retranslate() },
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

    private func copyTranslation() {
        let text = model.copyableText
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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