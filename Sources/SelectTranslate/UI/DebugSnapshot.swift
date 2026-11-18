import AppKit
import SwiftUI

/// 调试用：把翻译浮窗离屏渲染成 PNG，方便在没有屏幕录制权限时检查排版
@MainActor
enum DebugSnapshot {
    static func run() {
        let model = TranslationViewModel()
        model.original = "The quick brown fox jumps over the lazy dog. Machine translation quality depends on context."
        model.translation = "敏捷的棕色狐狸跳过了懒惰的狗。机器翻译的质量取决于上下文，而术语的准确性往往决定读者能否理解。"
        model.status = .done
        model.vocabulary = [
            VocabWord(word: "hypothesis", phonetic: "/haɪˈpɒθəsɪs/", pos: "n.", meaning: "假设；假说", level: "学术"),
            VocabWord(word: "robust", phonetic: "/rəʊˈbʌst/", pos: "adj.", meaning: "稳健的；鲁棒的", level: "IELTS"),
            VocabWord(word: "mitigate", phonetic: "/ˈmɪtɪɡeɪt/", pos: "v.", meaning: "减轻；缓解", level: "TOEFL"),
            VocabWord(word: "take into account", phonetic: "", pos: "phr.", meaning: "把……考虑在内", level: "常用")
        ]
        model.vocabState = .done

        if CommandLine.arguments.contains("--dictionary") {
            model.isWordMode = true
            model.original = "robust"
            model.translation = ""
            model.dictionary = DictionaryEntry(
                word: "robust",
                phonetic: "/rəʊˈbʌst/",
                level: "IELTS",
                senses: [
                    DictionarySense(
                        pos: "adj.",
                        meaning: "强健的；健壮的",
                        example: "He is a robust man who rarely gets ill.",
                        exampleTranslation: "他是个体格健壮、很少生病的人。"
                    ),
                    DictionarySense(
                        pos: "adj.",
                        meaning: "（系统、方法）稳健的，可靠的",
                        example: "The app needs a robust error-handling strategy.",
                        exampleTranslation: "这个应用需要一套稳健的错误处理策略。"
                    )
                ],
                synonyms: ["sturdy", "strong", "resilient"],
                note: "常与 system / design / evidence 搭配。"
            )
            model.dictState = .done
        }

        let root = TranslationView(model: model, panel: PanelState(), book: VocabBook.shared, onClose: {}, onCopy: {}, onCopyWord: { _ in })
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 440, height: 480)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            DebugLog.write("snapshot: no bitmap rep")
            NSApp.terminate(nil)
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/panel-snapshot.png"))
            DebugLog.write("snapshot written \(data.count) bytes")
        }
        NSApp.terminate(nil)
    }
}