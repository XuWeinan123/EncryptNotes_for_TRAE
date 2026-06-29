# AGENTS.md

EncryptNotes（“别看我”）是一款基于 SwiftUI 的、采用端到端加密的快速记录便签应用。它通过单一代码库构建并分发为两个 Target：**EncryptNotes** (iOS 17+) 和 **EncryptNotesMac** (macOS 26+)。

## 构建 / 运行 / 测试

本项目没有 SwiftPM 或 CocoaPods 配置文件 —— 它是一个 Xcode 项目 (`EncryptNotes.xcodeproj`)，使用 Swift 5。

- **运行 Mac 应用：** `./script/build_and_run.sh`（构建 Scheme `EncryptNotesMac`，终止任何运行中的实例，然后启动它）。可选参数：`--verify`（构建并确认进程已启动）、`--logs`、`--telemetry`（流式传输 `subsystem == com.biekanwo.EncryptNotesMac` 的日志）、`--debug`（使用 lldb 调试）。
- **手动构建 Target：** `xcodebuild -project EncryptNotes.xcodeproj -scheme EncryptNotesMac -destination 'platform=macOS' build`（或者构建带有 iOS 模拟器目标的 `EncryptNotes` Scheme）。
- **测试：** `EncryptNotesTests` Target 仅与 **`EncryptNotes`** (iOS) Scheme 绑定。运行命令：`xcodebuild test -project EncryptNotes.xcodeproj -scheme EncryptNotes -destination 'platform=iOS Simulator,name=iPhone 16'`。运行单个测试：在命令后追加 `-only-testing:EncryptNotesTests/CryptoServiceTests/<method>`。

## 平台隔离

共享代码位于 `EncryptNotes/` 的根目录下。平台特定的代码通过 `#if os(iOS)` / `#if os(macOS)` 以及 `Mac/` 子文件夹进行隔离，子文件夹包括：`App/Mac`、`Views/Mac`、`Stores/Mac`。macOS 版本是一个菜单栏应用（使用 `MacMenuBarController`、`NSStatusItem`），带有悬浮的便签窗口 (`StickyNoteWindow`)；iOS 版本则使用单一的 `WindowGroup` → `ContentView`。在添加新功能时，请先确定它是共享功能还是平台特定功能，然后再放置文件。

## 存储架构（核心抽象）

便签是 **Markdown 文件，而不是数据库**。每篇便签对应一个 `<noteId>.md` 文件：由 YAML 属性前言（frontmatter，包含 `note_id`、`created_at`、`updated_at`）和正文组成。`MarkdownNoteFile.parse(_:)` 负责手写的属性前言解析。

- `VaultStorage`（协议）对文件系统进行了抽象。有两个实现类：**`ICloudVaultStorage`**（首选）和 **`LocalFallbackStorage`**。`VaultStore` 在初始化时进行选择：如果 iCloud 可用 (`isAvailable`) 则选择 iCloud，否则选择本地存储 —— 参见 `Stores/VaultStore.swift:68`。文件存放在 `notes/` 和 `trash/` 子目录下 (`NoteFileLocation`)。
- `NoteIndex` (`index.json`) 是便签清单：每个便签的 `NoteIndexEntry` 记录了 `mode`（`.plain`/`.encrypted`）、`location` 以及废纸篓元数据（`deletedAt`、`purgeAfter`、`originalLocation`）。在修改便签时，请保持索引与实际的 `.md` 文件同步。
- **`VaultStore`**（`@MainActor`、`.shared` 单例、`ObservableObject`）是所有便签状态的唯一事实来源 —— 包括已解密的便签、明文便签、锁定的加密预览、废纸篓、搜索/标签过滤。UI 观察该对象，所有修改都通过它进行。

## 加密模型

- 钥匙串 (`KeychainStore`) 中存储了单一的 256 位对称保险库密钥 (`VaultKeyManager`)。该密钥可以导出/导入为 Base64 格式，以便相同的保险库可以在不同设备间解密 (`needsKeyExport`)。
- 每篇便签的加密**仅针对正文**：属性前言（frontmatter）保持明文，以便索引和同步仍能正常工作。`CryptoService.encryptMarkdownBody` 使用 AES-GCM 加密，布局为 `nonce ‖ ciphertext ‖ tag`，进行 base64url 编码，并带有字面前缀 **`bkwenc:v1:`**。`MarkdownNoteFile.isEncrypted` 根据该前缀进行判断 —— 如果该前缀发生变更，请确保 `MarkdownNoteFile` 和 `CryptoService` 中的 `encryptedPrefix` 保持一致。
- 当密钥缺失时，明文正文将通过 `NoteObfuscator` 显示为混淆的 base64 文本，以便锁定的内容在视觉上与真实的密文预览相匹配。

## 设计参考

`DESIGN.md` 包含了 flomo 风格的设计系统（颜色 Token、萍方/PingFang SC 字体、浅色/深色模式）。`DesignSystem.swift` 是其在 Swift 中的对应实现。在构建 UI 时，请匹配这些设计规范，而不要自行创建新的数值。

## 备注

- 规划文档（`开发计划.md`、`macOS开发计划.md`、`别看我_PRD_*.md`）使用中文编写，描述了产品意图和路线图。
- `script/` 是唯一的自动化脚本目录；CI 仅包含 `.github/workflows/auto-merge-owner-prs.yml`。

## 分平台规则

现在 mac 端笔记的容器样式已经很完美了，比如工具栏的透明，按钮的系统默认 glass button 效果，在接下来的需求中如果没有必要不要调整它