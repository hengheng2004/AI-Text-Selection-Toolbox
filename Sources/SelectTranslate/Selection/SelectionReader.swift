import AppKit
import ApplicationServices

enum SelectionReader {

    /// 申请辅助功能权限（首次会弹出系统授权引导）
    @discardableResult
    static func ensureAccessibilityPermission(prompt: Bool = true) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 读取当前 App 的选中文字：先走辅助功能，失败再用剪贴板兜底
    static func readSelectedText() -> String? {
        if let text = axSelectedText(), !text.trimmed.isEmpty {
            NSLog("[SelectTranslate] AX 取词成功，长度 \(text.count)")
            return text
        }
        if let text = ClipboardFallback.copySelection(), !text.trimmed.isEmpty {
            NSLog("[SelectTranslate] 剪贴板兜底取词成功，长度 \(text.count)")
            return text
        }
        return nil
    }

    private static func axSelectedText() -> String? {
        guard isTrusted else { return nil }

        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef else { return nil }
        let element = focusedRef as! AXUIElement

        // 大部分 App 直接给选中文本
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
           let text = value as? String, !text.isEmpty {
            return text
        }

        // 少数 App 只给选区范围，需要再取该范围的字符串
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() {
            let rangeValue = rangeRef as! AXValue
            var range = CFRange()
            if AXValueGetValue(rangeValue, .cfRange, &range), range.length > 0 {
                var stringRef: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(
                    element,
                    kAXStringForRangeParameterizedAttribute as CFString,
                    rangeValue,
                    &stringRef
                ) == .success, let text = stringRef as? String, !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}