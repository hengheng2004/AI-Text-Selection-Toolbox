# 划词翻译 macOS 工具 · 开发计划

> 目标：一个常驻菜单栏的 macOS 小工具，选中任意 App 里的文字（或在屏幕上框选一块区域 OCR），
> 在鼠标附近弹出译文；翻译/解释走用户自己填的大模型 API Key（OpenAI 兼容协议）。

---

## 1. 可行性结论

**好做，属于“中等难度、工作量主要在细节”的桌面工具，不是研究型项目。**

- 核心链路只有三段：**取到选中文字 → 调 LLM → 浮窗显示**，每段都有成熟的系统 API。
- 真正的难点不在功能，而在：
  1. 不同 App（Safari / Chrome / Preview / Word / Adobe / Electron 应用）暴露选中文本的方式不一致，需要「AX 接口 + 剪贴板模拟」双通道兜底；
  2. 全局快捷键、鼠标监听、悬浮窗不抢焦点这些**权限与窗口层级**的坑；
  3. 签名和 TCC 权限：每次重编译签名变了，辅助功能授权可能失效（开发期最烦人的一点）。
- 预计：**能用的 MVP 3–5 天，完整好用的版本 2–3 周**（业余时间），代码量约 2500–4000 行 Swift。

---

## 2. 产品形态与交互设计

### 触发方式（建议全做，按优先级）

| 优先级 | 方式 | 说明 | 实现难度 |
|---|---|---|---|
| P0 | **全局快捷键** `⌥D`（可改） | 读当前选中文字并翻译。最稳、最省事，先做这个 | 低 |
| P1 | **划词后浮出小图标** | 鼠标拖选松开后，在选区右下角出现小圆标，点一下翻译（类似 Bob / 沉浸式翻译） | 中 |
| P1 | **双击/三击后自动翻译** | 可选开关，双击取词、选中整句 | 中 |
| P2 | **框选截图 OCR 翻译** | 按住快捷键鼠标画框 → 截屏 → Vision OCR → 翻译。解决 PDF 扫描件、图片、视频字幕 | 中高 |
| P2 | **划线下划线手势** | 若你说的“划线”是指“用鼠标在文字下画一道线”，本质是按轨迹判定选区 + OCR，归入 P2 | 中高 |

> 建议先确认“划线”是指「鼠标拖选文字」还是「在屏幕上画框/画线做 OCR」——两者的技术路线不同（前者靠 AX，后者靠 ScreenCaptureKit）。

### 浮窗（Translation Panel）

- `NSPanel`，无边框、圆角、毛玻璃背景，出现在鼠标右下方，自动避让屏幕边缘。
- **不抢焦点**（`.nonactivatingPanel` + `.floating` level），这样在 PDF 里连续划词不会丢失阅读位置。
- 内容：原文（可折叠）、译文（流式逐字出现）、复制、朗读（`AVSpeechSynthesizer`）、重新生成、切模型/切语言、钉住成独立窗口。
- 快捷键：`Esc` 关闭，`⌘C` 复制译文。

### 附加能力（后续）

- 划词即译的历史记录（本地 SQLite / JSON）
- 术语表 / 提示词模板（学术、代码、口语、润色、解释）
- 本地缓存（同文本同模型命中缓存，省 token）
- 选中文本 + 上下文段落一起发（提升代词、缩写准确率）
- 支持 Ollama / LM Studio 本地模型（隐私场景）

---

## 3. 技术选型

### 推荐：原生 Swift + SwiftUI/AppKit（菜单栏 App，不进 Dock）

理由：
- 全局取词、辅助功能、屏幕捕获、悬浮窗、Keychain 全是原生能力，用别的框架要绕桥接；
- 体积小（< 10 MB）、启动快、常驻内存低；
- 需要 **Accessibility 权限**，而沙盒应用拿不到，所以必然是「非沙盒 + 开发者签名分发」，原生最顺。

| 方案 | 优点 | 缺点 | 结论 |
|---|---|---|---|
| **Swift + SwiftUI/AppKit** | 系统能力直接可用、轻量 | 只能 macOS | ✅ 主选 |
| Tauri (Rust + Web UI) | UI 好写、跨平台 | 调 AX/ScreenCaptureKit 要写 Rust-ObjC 绑定，权限调试更痛 | 备选 |
| Electron | 生态熟 | 100 MB+、常驻内存高、系统级取词仍要原生插件 | ❌ 不建议 |
| Raycast 扩展 / Hammerspoon 脚本 | 几小时出原型 | UI 受限、依赖宿主 App | 用于**快速验证交互** |

### 大模型接入：统一走 OpenAI 兼容协议

一个 `baseURL + apiKey + model` 就能覆盖 OpenAI、DeepSeek、Kimi、GLM、通义、SiliconFlow、OpenRouter、Ollama……
不要为每家写适配器，只在设置页提供「预设 + 自定义」。

- 流式：`POST {baseURL}/chat/completions`，`stream: true`，用 `URLSession.bytes(for:)` 解析 SSE。
- 参数：`temperature 0.2`、限制 `max_tokens`、超时 30s、可取消（Task cancellation）。
- System prompt 固定为“专业翻译引擎，只输出译文，保留术语/公式/格式”，避免模型加解释。
- 可选内置兜底：Apple 的 `Translation` 框架（macOS 15+，离线、免费、快），没配 Key 时也能用。

---

## 4. 模块划分

```
SelectTranslate/
├── App/
│   ├── SelectTranslateApp.swift      // @main, MenuBarExtra
│   ├── AppDelegate.swift             // 权限申请、全局热键、生命周期
│   └── Info.plist                    // LSUIElement = true
├── Capture/
│   ├── SelectionReader.swift         // AX 读取选中文本 + 剪贴板兜底
│   ├── ClipboardFallback.swift       // 模拟 ⌘C，取完恢复剪贴板
│   ├── MouseWatcher.swift            // 全局鼠标抬起检测、拖选判定
│   └── RegionOCR.swift               // ScreenCaptureKit 截图 + Vision OCR
├── Translation/
│   ├── LLMClient.swift               // OpenAI 兼容流式请求
│   ├── PromptBuilder.swift           // 翻译/解释/润色模板
│   ├── TranslationCache.swift        // SHA256 缓存
│   └── AppleTranslator.swift         // 可选离线兜底
├── UI/
│   ├── TranslationPanel.swift        // 悬浮窗（NSPanel）
│   ├── SettingsView.swift            // API Key / 模型 / 快捷键 / 语言
│   ├── HistoryView.swift
│   └── PermissionGuide.swift         // 权限引导
├── Storage/
│   ├── KeychainStore.swift           // API Key 存 Keychain
│   └── Settings.swift                // @AppStorage
└── Resources/
```

---

## 5. 关键技术点（决定成败的细节）

### 5.1 取选中文字

```swift
// 1) 优先：Accessibility API，不污染剪贴板
let system = AXUIElementCreateSystemWide()
var focused: CFTypeRef?
AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
var selected: CFTypeRef?
AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected)
// 返回 nil 时，再试 kAXSelectedTextRange + kAXStringForRange（部分 App 只给范围）

// 2) 兜底：模拟 ⌘C，轮询 changeCount，取完把旧剪贴板还原
```

- 覆盖率：Safari/Chrome/Preview/Pages/Word/大部分原生 App 的 AX 都可用；
- Adobe Acrobat、部分 Electron 应用（Slack/VSCode 某些版本）需要剪贴板兜底；
- 剪贴板兜底的副作用：会闪一下、打断剪贴板管理器，所以**只在 AX 失败时用**，并且 200ms 内还原。

### 5.2 悬浮窗不抢焦点

```swift
let panel = NSPanel(contentRect: rect,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
panel.level = .floating
panel.isFloatingPanel = true
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
panel.hidesOnDeactivate = false
panel.becomesKeyOnlyIfNeeded = true
panel.orderFrontRegardless()
```
> 想让用户能在浮窗里选中文字复制，就设 `becomesKeyOnlyIfNeeded = false` 并 `makeKeyAndOrderFront`，但会抢走源 App 焦点——建议用「复制按钮」代替。

### 5.3 权限（三件套，缺一不可）

| 权限 | 用途 | 申请方式 |
|---|---|---|
| 辅助功能 Accessibility | 读选中文本、全局热键、鼠标事件 | `AXIsProcessTrustedWithOptions(prompt: true)` |
| 屏幕录制 Screen Recording | 框选 OCR | `CGRequestScreenCaptureAccess()` |
| 输入监控 Input Monitoring | `CGEventTap` 监听鼠标（仅划词浮标需要） | `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` |

- **首次启动必须有引导页**，告诉用户去「系统设置 → 隐私与安全性 → 辅助功能」勾选，并提供一键跳转（`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`）。
- **开发期大坑**：每次重新编译签名变化，TCC 可能认为这是新 App。解决办法：在钥匙串里创建一个**自签名代码签名证书**，固定用它签名（`codesign -s "My Local Dev"`），授权就不会反复失效。
- 应用**不能开 App Sandbox**（开了就拿不到 AX），所以只能走 Developer ID 分发，上不了 Mac App Store。

### 5.4 流式输出

```swift
let (bytes, _) = try await URLSession.shared.bytes(for: request)
for try await line in bytes.lines where line.hasPrefix("data: ") {
    let json = line.dropFirst(6)
    if json == "[DONE]" { break }
    // 解析 choices[0].delta.content，追加到 @Published 文本
}
```
注意：不要在主线程做 JSON 解析；请求可取消；网络错误要有可读提示（401 = Key 错，429 = 限流，超时 = 换模型）。

### 5.5 成本与体验

- 划词翻译单次约 300–800 token，DeepSeek 级别模型一次不到 0.001 元；
- 必须做**本地缓存 + 去抖**（连续划词时取消上一次请求），否则会浪费钱且闪烁；
- 加「停止生成」，长文本才不至于卡住。

---

## 6. 分阶段计划

### P0 · 技术验证（0.5–1 天）
**目标：证明「能取到别的 App 的选中文字」**
- [ ] 建一个最小 SwiftUI App，申请辅助功能权限
- [ ] 用 AX 读取 Safari / Preview 的选中文字并打印
- [ ] 模拟一次 ⌘C 兜底并还原剪贴板
- ✅ 验收：在 5 个常用 App 里至少 4 个能取到文字

### P1 · 可用 MVP（3–5 天）
**目标：`⌥D` 一按，鼠标旁弹出流式译文**
- [ ] 菜单栏图标 + 设置页（baseURL / Key / model / 目标语言）
- [ ] Keychain 存 Key，OpenAI 兼容流式客户端
- [ ] 翻译 Prompt（只输出译文）+ 取消 + 错误提示
- [ ] 悬浮窗（不抢焦点、跟随鼠标、Esc 关闭、复制按钮）
- [ ] 全局热键（Carbon `RegisterEventHotKey` 或 `MASShortcut`）
- [ ] ✅ 验收：在 Safari 读英文论文，选中一段按 ⌥D，2 秒内看到中文

### P2 · 划词气泡 + OCR 框选（2–4 天）
- [ ] 全局鼠标监听：拖选结束（位移 > 阈值）后读选区，浮出小图标
- [ ] 点击图标翻译；设置里可关
- [ ] `SCScreenshotManager` 框选截图（自绘选区遮罩层）
- [ ] Vision OCR（`VNRecognizeTextRequest`，中英混排、竖排要测）
- [ ] ✅ 验收：扫描版 PDF / 图片 / 视频暂停帧都能框选翻译

### P3 · 打磨到「愿意天天用」（约 1 周）
- [ ] 历史记录、缓存、术语表
- [ ] 上下文增强（把选区所在段落一起发给模型）
- [ ] 多套 Prompt 预设（学术 / 代码 / 口语 / 润色 / 解释）
- [ ] TTS 朗读、钉住窗口、多屏适配
- [ ] 开机自启（`SMAppService.mainApp`）、浅色/深色、快捷键录制
- [ ] 大文本截断与分块、并发去重
- [ ] ✅ 验收：连续使用一天不崩、不抢焦点、不卡输入

### P4 · 签名与分发（1–2 天，仅当要给别人用）
- [ ] Developer ID 证书（$99/年）+ Hardened Runtime
- [ ] `notarytool` 公证 + `stapler` 装订，否则别人打开会被 Gatekeeper 拦
- [ ] 自动更新（Sparkle）可选
- [ ] 自己用则 ad-hoc 签名 + 自签名证书即可，0 成本

---

## 7. 环境准备

当前机器状态：

- macOS 27，Swift 6.4 可用
- **只装了 Command Line Tools，没有完整 Xcode**（`xcode-select -p` 指向 `/Library/Developer/CommandLineTools`）

两条路：

1. **装 Xcode（推荐）**：App Store 安装，约 40 GB。有 SwiftUI 预览、调试器、签名管理，开发效率高一个档。
2. **不装 Xcode**：用 SwiftPM 写，`swift build` 出可执行文件，再手工组装 `.app`（Info.plist + Contents/MacOS），`codesign -s -` 签名。完全可行，但调试悬浮窗/权限会麻烦很多。

> 另外：工程目录建议用**英文名**（如 `SelectTranslate`），显示名再设成中文「划词翻译」。中文路径偶尔会让构建脚本、签名工具出问题。

---

## 8. 风险清单

| 风险 | 影响 | 应对 |
|---|---|---|
| 某些 App 拿不到 AX 选中文本 | 功能失效 | 剪贴板兜底 + OCR 兜底，三层保险 |
| TCC 授权反复失效 | 开发体验差 | 固定自签名证书，不要每次变签名 |
| 悬浮窗抢焦点 | 打断阅读 | `nonactivatingPanel`，测 PDF 连续划词 |
| 全局鼠标监听耗电/卡顿 | 被用户卸载 | 事件回调里只做轻量判断，重活丢后台 |
| 屏幕录制权限被拒 | OCR 不可用 | 降级为「翻译选中文本」并引导授权 |
| API Key 泄露 | 安全问题 | 只存 Keychain，绝不写 UserDefaults / 日志 |
| 云模型隐私 | 用户顾虑 | 提供 Ollama 本地模型选项 |
| 分发被 Gatekeeper 拦 | 别人装不上 | 公证 notarize，或提供「右键打开」说明 |

---

## 9. 如果只想「今天就能用」

在动手写原生 App 之前，可以先用下面任一方式验证交互是否合你心意：

- **Raycast 扩展**：调用选中文字 + 调 LLM，1–2 小时能跑通；
- **Hammerspoon 脚本**：`hs.hotkey` + `hs.eventtap` + `hs.pasteboard`，约 100 行 Lua；
- **快捷指令（Shortcuts）+ 服务菜单**：零代码但交互一般。

验证完之后再把交互搬进原生 App，能少走很多弯路。

---

## 10. 下一步

1. 确认「划线」的确切含义（拖选文字 / 画框 OCR）；
2. 确认技术栈（原生 Swift 推荐）；
3. 决定是否先装 Xcode；
4. 我就可以直接开工 P0：搭工程骨架 + 打通「读选中文字 → 调 API → 悬浮窗显示」这条最小链路。