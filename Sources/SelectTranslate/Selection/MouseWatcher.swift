import AppKit

/// 监听全局鼠标：检测「拖选」动作，松开后读取选中文字并回调
@MainActor
final class MouseWatcher {
    var onDragSelection: ((String, NSPoint) -> Void)?
    var onMouseDown: ((NSPoint) -> Void)?
    var shouldIgnorePoint: ((NSPoint) -> Bool)?

    private var monitors: [Any] = []
    private var downPoint: NSPoint?
    private var lastText: String?
    private var lastShownAt = Date.distantPast

    private let dragThreshold: CGFloat = 8

    func start() {
        stop()

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }) {
            monitors.append(global)
        } else {
            DebugLog.write("MouseWatcher: 全局鼠标监听注册失败（检查辅助功能权限）")
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    private func handle(_ event: NSEvent) {
        let point = NSEvent.mouseLocation

        switch event.type {
        case .leftMouseDown:
            downPoint = point
            onMouseDown?(point)

        case .leftMouseUp:
            guard let start = downPoint else { return }
            downPoint = nil

            let distance = hypot(point.x - start.x, point.y - start.y)
            guard distance >= dragThreshold else { return }
            guard !NSApp.isActive else { return }
            if shouldIgnorePoint?(point) == true { return }

            // 等 App 把选区状态更新完，再读一次
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let text = SelectionReader.readSelectedText()?.trimmed,
                      !text.isEmpty, text.count <= 8000 else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    let now = Date()
                    if text == self.lastText, now.timeIntervalSince(self.lastShownAt) < 1.2 { return }
                    self.lastText = text
                    self.lastShownAt = now
                    self.onDragSelection?(text, point)
                }
            }

        default:
            break
        }
    }
}