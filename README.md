# 划词翻译（macOS 菜单栏小工具）

选中任意 App 里的文字 → 鼠标旁弹出译文。翻译走你自己的大模型 API（OpenAI 兼容协议），
Key 只存本机（优先 Data Protection 钥匙串，系统不支持时退回仅本人可读的 0600 文件），不会弹钥匙串授权框。

除了翻译，还可以选中专业术语直接打开一个临时问答框，让 AI 解释并继续追问，满意的回答可以收藏。

## 现在能做什么

- 菜单栏常驻，不占 Dock
- 全局快捷键 `⌥D`：读取当前选中文字并翻译
- **解释模式**：选中术语后按 `⌥E`，或点气泡上的问号按钮，打开问答框；AI 先给定义，再结合语境解释，可以继续追问
- **临时对话 + 收藏**：解释会话不写入历史，关掉就没了；每条回答下方的「收藏」会把这一轮问答存进「解释收藏…」，可搜索、复制、删除、清空
- 鼠标拖选文字后，在松开位置浮出小气泡按钮（翻译 / 解释），点一下才开始请求，可在设置里关闭
- 悬浮翻译窗：流式输出、复制译文、Esc 关闭、点击窗外自动收起
- **固定 / 置顶**：点右上角图钉，浮窗就悬浮在桌面上，点别处也不收起，切换桌面也跟着显示（翻译窗和解释窗各自记忆）
- **浮窗可拖动**：按住标题栏左侧的拖动把手（三条横线）就能移动位置，拖动过程中不会误触复制或按钮
- **生词本**：译文里的生词点右侧 `+` 收录，查单词时点「加入生词本」；菜单栏 →「生词本…」可搜索、复制、删除、清空
- **结果缓存**：同一段文字 + 同样的模型配置再翻译时直接出结果，不再发请求；浮窗里的刷新按钮可忽略缓存重译
- **单词自动查词典**：选中的是一个单词（含 `robust,` 这种带标点的情况）时，输出词典式条目——音标、词性、多个义项、例句及翻译、近义词、搭配提醒
- **译文下方列出难词**：单词、音标、词性、结合语境的释义、雅思/托福/学术标签，点击单词即复制
- 生词和译文并发请求，译文先出现，生词随后补齐，互不阻塞
- 取词双通道：Accessibility API 优先，失败时自动用「模拟 ⌘C + 还原剪贴板」兜底
- 设置页：Base URL / 模型 / API Key / 目标语言 / 常用服务预设，支持一键「拉取模型」并下拉选择
- 译文流式渲染，请求可被下一次翻译打断
- 附带 `models-list` 命令行工具：填 Base URL + API Key 就能列出所有可用模型

## 构建与运行

不需要完整 Xcode，也不需要苹果开发者账号。

签名用本地自签证书 `SelectTranslate Local Dev`，私钥放在独立钥匙串
`~/Library/Keychains/selecttranslate-signing.keychain-db`（空密码、已授权所有程序访问），
因此每次重新编译都不会弹钥匙串授权框，辅助功能授权也不会因为重新编译而失效。

```bash
./Scripts/build-app.sh     # 构建到 build/划词翻译.app
open "build/划词翻译.app"
```

## 拉取可用模型（命令行）

同一个 Swift Package 里附带 `models-list`，输入 Base URL 和 API Key 就能列出
这个 Key 可访问的所有模型，方便往设置里填模型名。兼容 OpenAI 协议的服务都能用
（DeepSeek / OpenAI / Kimi / GLM / Ollama / LM Studio 等）。

```bash
swift run models-list -b https://api.deepseek.com/v1 -k sk-xxxx
```

不带参数运行会交互输入，API Key 不回显：

```text
$ swift run models-list
Base URL（例如 https://api.deepseek.com/v1）: https://api.deepseek.com/v1
API Key（输入不回显，本地服务可直接回车跳过）:
共 2 个可用模型

deepseek-chat
deepseek-reasoner
```

常用选项：

| 选项 | 作用 |
|---|---|
| `-b, --base-url` | Base URL，带不带 `/v1` 都行，填到 `/chat/completions` 也认 |
| `-k, --api-key` | API Key，也可用 `LLM_API_KEY` / `OPENAI_API_KEY` 环境变量 |
| `--ids` | 只输出模型 ID（输出到管道时自动启用） |
| `-v, --verbose` | 附带 `owned_by` 和创建时间 |
| `--json` | 打印服务端返回的原始 JSON |
| `--timeout` | 请求超时秒数，默认 20 |

```bash
# 直接复制模型名
LLM_API_KEY=sk-xxx swift run models-list -b https://api.deepseek.com/v1 | pbcopy

# 看详情
swift run models-list https://api.deepseek.com/v1 sk-xxx -v

# 本地 Ollama 不需要真 Key
swift run models-list -b http://127.0.0.1:11434/v1
```

编译成独立可执行文件：

```bash
swift build -c release --product models-list
.build/release/models-list -b https://api.deepseek.com/v1 -k sk-xxx
```

> 只填域名（例如 `https://api.openai.com`）时，如果 `/models` 返回 404，会自动再试 `/v1/models`。
> 服务不提供 `/models` 接口时会直接报错并带上服务端返回内容。

## 首次使用

1. 启动后菜单栏出现气泡图标。
2. 系统会提示辅助功能权限：**系统设置 → 隐私与安全性 → 辅助功能**，勾选「划词翻译」。
   勾选后退出并重新打开 App（菜单 → 退出）。
3. 菜单栏 → 设置…，填入：
   - Base URL，例如 `https://api.deepseek.com/v1`
   - API Key
   - 点一下模型输入框右侧的「拉取模型」，下拉框会列出当前 Key 可用的所有模型；选一个，点「保存」即可。
   - 如果服务不提供 `/models` 接口（例如部分中转或本地服务），也可以直接手动填写模型名。
   - 目标语言
   点「保存」。

生词默认开启，可在设置里关掉（每翻译一次会多一次模型请求，长文本会自动截取前 3000 字符提取生词）。
4. 在 Safari / Preview / 备忘录里选中一段英文，按 `⌥D` 翻译，或直接拖选后点气泡里的翻译按钮。
5. 遇到看不懂的术语，选中后按 `⌥E`（或点气泡里的问号），打开解释框可以直接追问；点回答下方的「收藏」保存。

> 想用本地模型：Base URL 填 `http://127.0.0.1:11434/v1`，模型填 `qwen2.5:7b`，Key 随便填一个非空值。

## 交互细节

| 操作 | 结果 |
|---|---|
| 拖选文字 | 鼠标旁浮出翻译 + 解释两个气泡按钮（设置里可关） |
| `⌥D` | 翻译当前选区 |
| `⌥E` | 解释当前选区，打开临时问答框 |
| 点气泡的翻译按钮 | 翻译对应选中内容 |
| 点气泡的问号按钮 | 打开解释问答框 |
| 解释框输入框按 `⏎` | 发送追问（回答过程中不可发送） |
| 回答下方「收藏」 | 收藏这一轮问答；再点一次取消 |
| 菜单「解释收藏…」 | 打开收藏夹，可搜索、复制、删除、清空 |
| `Esc` / 点窗外 / 点关闭 | 收起浮窗（固定状态下点窗外不收起） |
| 按住标题栏左侧把手拖动 | 移动浮窗 |
| 点复制按钮 | 复制译文 / 复制该条解释回答 |
| 点生词条目 | 复制该单词 |
| 点生词右侧 `+` / `✓` | 加入 / 移出生词本 |
| 词典模式点「加入生词本」 | 收录当前单词 |
| 菜单「生词本…」 | 打开生词本，可搜索、复制、删除、清空 |
| 选中单个单词 | 自动切换词典模式（不会去翻成一句话） |
| 词典模式点近义词 | 复制该词 |
| 点图钉 | 固定 / 取消固定（翻译窗和解释窗分别记忆） |
| 点刷新按钮 | 忽略缓存，重新请求一次 |
| 菜单「清除翻译缓存」 | 清空本地缓存（最多保留 300 条） |

## 本地数据

都放在 `~/Library/Application Support/SelectTranslate/`：

| 文件 | 内容 |
|---|---|
| `translation-cache.json` | 译文 / 生词 / 词典结果缓存（最多 300 条，LRU 淘汰） |
| `vocab-book.json` | 生词本（单词、音标、词性、释义、标签、原文语境、收录时间） |
| `explain-favorites.json` | 解释收藏（选中内容、当轮提问、回答、收藏时间） |
| `api-key` | 钥匙串不可用时的 API Key 兜底文件（权限 0600） |

生词本和解释收藏都没有云同步，删掉对应 JSON 就相当于清空；解释会话本身不落盘，关窗即丢弃。

## 调试参数

```bash
# 用示例文本直接开浮窗，不读选区
open "build/划词翻译.app" --args --demo

# 直接打开设置窗口
open "build/划词翻译.app" --args --settings

# 离屏渲染浮窗为 /tmp/panel-snapshot.png 后退出
open "build/划词翻译.app" --args --snapshot

# 渲染词典模式浮窗（配合 --dictionary）
open "build/划词翻译.app" --args --snapshot --dictionary

# 直接查一个单词（走词典模式）
open "build/划词翻译.app" --args --word robust

# 打开生词本窗口
open "build/划词翻译.app" --args --vocab

# 离屏渲染生词本为 /tmp/vocab-snapshot.png 后退出
open "build/划词翻译.app" --args --snapshot-vocab

# 打开解释浮窗（可带一个自定义术语）
open "build/划词翻译.app" --args --explain "attention mechanism"

# 离屏渲染解释浮窗为 /tmp/explain-snapshot.png 后退出
open "build/划词翻译.app" --args --snapshot-explain

# 跑一轮追问 + 收藏，渲染会话和收藏夹
open "build/划词翻译.app" --args --snapshot-explain-thread

# 打开解释收藏窗口 / 渲染为 /tmp/favorites-snapshot.png
open "build/划词翻译.app" --args --favorites
open "build/划词翻译.app" --args --snapshot-favorites

# 渲染划词气泡为 /tmp/bubble-snapshot.png
open "build/划词翻译.app" --args --snapshot-bubble
```

运行日志写在 `/tmp/selecttranslate-debug.log`。

## 目录结构

```
Sources/
├── ModelsList/
│   └── ModelsList.swift           # 命令行 models-list（拉取可用模型）
└── SelectTranslate/
    ├── main.swift                 # 入口
    ├── AppDelegate.swift          # 菜单栏、权限、流程编排
    ├── HotKey/GlobalHotKey.swift  # Carbon 全局热键
    ├── Selection/
    │   ├── SelectionReader.swift  # AX 读取选中文字
    │   ├── ClipboardFallback.swift # ⌘C 兜底 + 剪贴板还原
    │   └── MouseWatcher.swift     # 全局鼠标拖选检测
    ├── Translation/
    │   ├── LLMConfig.swift        # 配置读取
    │   ├── PromptBuilder.swift    # 翻译 / 解释提示词
    │   ├── LLMClient.swift        # OpenAI 兼容流式客户端（翻译 + 多轮对话）
    │   ├── Vocabulary.swift       # 生词模型 / 提示词 / JSON 解析
    │   ├── Dictionary.swift       # 单词词典条目 / 提示词 / JSON 解析
    │   └── TranslationCache.swift # 译文、生词、词典结果缓存（最多 300 条）
    ├── Support/
    │   ├── Keychain.swift         # API Key 存储（钥匙串优先 + 0600 文件兜底）
    │   ├── VocabBook.swift        # 生词本模型与 JSON 持久化
    │   └── ExplainFavorites.swift # 解释收藏模型与 JSON 持久化
    └── UI/
        ├── TranslationPanel.swift # 翻译浮窗（不抢焦点的 NSPanel）
        ├── TranslationView.swift  # SwiftUI 内容
        ├── TranslationViewModel.swift
        ├── ExplainPanel.swift     # 解释浮窗（可拖动 / 固定 / Esc 关闭）
        ├── ExplainView.swift      # 解释会话界面
        ├── ExplainViewModel.swift # 临时多轮会话状态
        ├── PanelState.swift       # 固定状态（翻译 / 解释各自跨启动记住）
        ├── StatusWindowController.swift # 状态与诊断窗口
        ├── VocabBookWindowController.swift # 生词本窗口（AppKit）
        ├── ExplainFavoritesWindowController.swift # 解释收藏窗口（AppKit）
        ├── SelectionBubbleController.swift
        ├── SettingsWindowController.swift
        └── DebugSnapshot.swift
```

## 已知限制

- 部分应用（Adobe Acrobat、个别 Electron 应用）不暴露 AX 选区，会走剪贴板兜底，可能有轻微闪烁。
- 首次授权需要手动操作；重编译后如果权限失效，去辅助功能列表里删掉再重新添加。
- 暂时只有翻译、单词词典和解释问答，没有 OCR / 翻译历史（见 `PLAN.md` 的 P2、P3）。
- 生词本和解释收藏没有云同步与导出，删除对应 JSON 即清空。
- `⌥E` 会全局占用 Option+E（在部分键盘布局下这个组合用于输入重音字符）。
- 暂未公证，分发给别人需要 Developer ID；自己用不受影响。

## 接下来可以加

- 框选截图 OCR 翻译（PDF 扫描件、图片、视频）
- 术语表与提示词预设（学术 / 代码 / 润色 / 解释）
- 翻译历史记录、生词本导出（CSV / Anki）
- 可自定义快捷键
- 朗读（AVSpeechSynthesizer）
- 开机自启（SMAppService）