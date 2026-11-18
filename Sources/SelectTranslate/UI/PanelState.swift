import SwiftUI

/// 浮窗的显示状态（固定 / 取消固定），跨次启动记住选择。
/// 翻译和解释各自用不同的 key，互不影响。
@MainActor
final class PanelState: ObservableObject {
    @Published var isPinned: Bool

    private let pinKey: String

    init(key: String = "panelPinned") {
        pinKey = key
        isPinned = UserDefaults.standard.bool(forKey: key)
    }

    func togglePin() {
        isPinned.toggle()
        UserDefaults.standard.set(isPinned, forKey: pinKey)
        DebugLog.write("浮窗固定（\(pinKey)）：\(isPinned)")
    }
}