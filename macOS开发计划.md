# 《别看我》macOS v0.1 开发计划

> 本计划基于根目录 `别看我_macOS_PRD_v0.1.md` 制定，目标是方便交给其他模型或开发者直接执行。  
> macOS v0.1 的产品形态：**菜单栏 App + 独立悬浮便利贴窗口 + iCloud 文件同步 + 本地 AES-GCM 加密 + 回收站**。

---

## 0. 总体目标

在当前 iOS 仓库中新增一个原生 macOS App Target，而不是新开仓库。macOS 端复用现有移动端的核心数据协议、加密 schema、iCloud 目录与 Keychain 本机密钥保存逻辑，同时新增 macOS 专属的菜单栏、全局快捷键、便利贴窗口与列表/回收站 UI。

最终闭环：

```text
菜单栏或全局快捷键
→ 新建默认置顶便利贴
→ 可选择明文或加密笔记
→ 自动保存为独立 JSON 文件
→ 通过 iCloud 同步
→ 正确加载 .bkwkey 后本机解密加密笔记
→ 删除进入 trash，可恢复/永久删除/清空
```

---

## 1. 基本原则与硬约束

### 1.1 仓库与工程组织

- 不新开仓库。
- 在当前 `EncryptNotes.xcodeproj` 中新增 macOS App Target：建议命名为 `EncryptNotesMac`。
- macOS App 使用原生 SwiftUI macOS target，不优先使用 Catalyst。
- iOS 与 macOS 共用核心代码，平台 UI 分离。
- macOS 最低系统版本：macOS 14.0。

### 1.2 数据与安全约束

- 继续使用同一个 iCloud container：`iCloud.com.biekanwo.EncryptNotes`。
- 继续使用同一目录结构：

```text
iCloud Drive / 别看我 /
  vault.json
  notes/
    <note_id>.bkwplain.json
    <note_id>.bkwenc.json
  trash/
    <note_id>.bkwplain.json
    <note_id>.bkwenc.json
  meta/
```

- 明文笔记保存为 `.bkwplain.json`。
- 加密笔记保存为 `.bkwenc.json`。
- 密钥文件保存为 `.bkwkey`。
- 加密笔记沿用移动端 AES-GCM 加密方案和加密文件结构。
- 明文笔记 schema 以现有 `PlainNoteFile` 为准，正文使用 `body` 字段；PRD 示例中的 `content` 仅作语义示例，不新增第二套明文字段。
- 继续保留现有明文文件中的 `vault_id`、`deleted_at`、`purge_after`、`original_location` 等字段，用于跨端兼容与回收站能力。
- 加密 JSON 外层不得保存正文、标题、第一行预览、摘要、标签、搜索索引。
- 未加载密钥时不得生成任何明文预览缓存。
- 错误密钥不得展示任何明文，不得修改现有笔记文件。
- 密钥只保存到本机 Keychain，不写入 iCloud Drive，不通过 iCloud Keychain 同步。
- 文案使用“加载密钥文件”，说明文案统一为：`密钥文件只会在本机读取，不会上传。`

### 1.3 v0.1 不做

- 不做 Markdown、Checklist、颜色、图片、附件、语音、AI、富文本。
- 不做账号系统、自建服务器、Web、Android、多人协作。
- 不做所有 Desktop 显示、隐私隐藏、透明度、折叠便签、开机启动。
- 不做付费分层与订阅。
- 不承诺全屏 App 上方显示。

### 1.4 本轮核查后的确认取舍

- macOS v0.1 复用现有 iOS `VaultStore` 的默认示例笔记、正文 `#tag` 解析、标签筛选状态与正文搜索状态。
- 标签与搜索只复用当前正文级能力，不新增标签 schema、外层搜索索引、服务端搜索或复杂管理功能。
- macOS v0.1 复用现有回收站自动清理行为：删除时写入 `purge_after`，超过期限后可自动永久删除。
- 冲突副本按现有策略处理：复制原文件并在文件名追加 `-conflict-<timestamp>`；内部 `note_id` 可以沿用原值。

---

## 2. 推荐目录结构

第一阶段尽量少移动已有文件，先通过 target membership 复用现有核心。完成 v0.1 后再考虑物理目录重构。

### 2.1 短期落地结构

```text
EncryptNotes/
  App/
    EncryptNotesApp.swift                 # 现有 iOS 入口
    Mac/
      EncryptNotesMacApp.swift            # 新增 macOS 入口
      MacAppDelegate.swift                # 菜单栏、Dock 隐藏、全局快捷键注册
  Models/                                 # iOS/macOS 共享
  Crypto/                                 # iOS/macOS 共享
  Storage/                                # iOS/macOS 共享
  Stores/                                 # 部分共享，新增 macOS store
    MacNoteWindowStore.swift
    ShortcutStore.swift
    SyncStatusStore.swift
  Utils/                                  # iOS/macOS 共享
  Views/
    Components/                           # 尽量共享通用组件
    Mac/
      MacMenuBarController.swift
      StickyNoteWindow.swift
      StickyNoteEditorView.swift
      LockedStickyNoteView.swift
      AllNotesWindow.swift
      TrashWindow.swift
      MacSettingsView.swift
      SyncStatusView.swift
      PlainStatusBadge.swift
```

### 2.2 中期理想结构

```text
Shared/
  Models/
  Crypto/
  Storage/
  Stores/
  Utils/
  DesignSystem/
  Views/Components/
Apps/
  iOS/
  macOS/
Tests/
  SharedTests/
  iOSTests/
  macOSTests/
```

> 注意：目录重构建议单独 PR，避免和 macOS 功能开发混在一起。

---

## 3. Target 与能力配置

### 3.1 新增 Target

新增 macOS App Target：

- Product Name：`EncryptNotesMac`
- Bundle ID：建议 `com.biekanwo.EncryptNotes.mac`
- Deployment Target：macOS 14.0
- App Sandbox：开启
- iCloud Documents：开启
- Ubiquity Containers：`iCloud.com.biekanwo.EncryptNotes`
- 默认不显示 Dock 图标：通过 `LSUIElement = YES` 或运行时 activation policy 处理。

### 3.2 macOS entitlements

新增文件：

```text
EncryptNotes/EncryptNotesMac.entitlements
```

至少包含：

- App Sandbox
- iCloud Documents
- iCloud container：`iCloud.com.biekanwo.EncryptNotes`
- User Selected File Read/Write，用于加载/导出 `.bkwkey`

### 3.3 共享文件 target membership

加入 macOS target：

- `Models/*`
- `Crypto/*`
- `Storage/*`
- `Utils/*`
- `Stores/VaultStore.swift`
- 与 schema / JSON / 乱码 / tag parsing 相关代码

需要检查并用条件编译处理的平台差异：

```swift
#if os(macOS)
// macOS-specific
#else
// iOS-specific
#endif
```

---

## 4. 模块拆分计划

## 4.1 App 启动与菜单栏模块

### 目标

App 启动后只显示菜单栏图标，不显示 Dock 图标。菜单栏是 v0.1 主入口。

### 文件建议

```text
EncryptNotes/App/Mac/EncryptNotesMacApp.swift
EncryptNotes/App/Mac/MacAppDelegate.swift
EncryptNotes/Views/Mac/MacMenuBarController.swift
```

### 功能

- 创建 `MenuBarExtra` 或 `NSStatusItem`。
- 默认隐藏 Dock 图标。
- 启动时初始化 `VaultStore.shared.initialize()`。
- 菜单项：

```text
新建明文笔记                 ⌥⌘N
新建加密笔记                 ⌥⇧⌘N

最近笔记
  笔记第一行……
  加密笔记第一行……
  加密笔记 · 未加载密钥
  最多显示 8 条

全部笔记…
回收站…

加载密钥文件… / 移除本机密钥
设置…
退出《别看我》
```

### 验收

- 启动后菜单栏出现入口。
- 默认不显示 Dock 图标。
- 菜单项可触发对应动作。
- 最近笔记最多 8 条，按 `updated_at` 倒序。
- 明文笔记显示第一行非空文本。
- 加密笔记在密钥已加载时显示解密后的第一行。
- 加密笔记在未加载密钥时只显示：`加密笔记 · 未加载密钥`。
- 未解锁的加密笔记不得生成明文预览缓存。

---

## 4.2 全局快捷键模块

### 目标

支持通过全局快捷键快速新建明文/加密便利贴。

### 文件建议

```text
EncryptNotes/Stores/ShortcutStore.swift
EncryptNotes/Views/Mac/MacSettingsView.swift
```

### 默认快捷键

| 操作 | 默认快捷键 |
|---|---|
| 新建明文笔记 | `⌥⌘N` |
| 新建加密笔记 | `⌥⇧⌘N` |

### 实现建议

- v0.1 可先使用 Carbon `RegisterEventHotKey`，或接入轻量封装。
- 设置页允许修改快捷键。
- 快捷键配置保存到 `UserDefaults`。
- 快捷键冲突时提示用户重新设置。

### 验收

- 默认快捷键生效。
- 快捷键触发后新建窗口立即出现并获得焦点。
- 设置中修改后立即生效或重启 App 后生效。

---

## 4.3 便利贴窗口管理模块

### 目标

每条打开的笔记对应一个独立便利贴窗口。新建和打开的窗口默认 Pin。

### 文件建议

```text
EncryptNotes/Stores/MacNoteWindowStore.swift
EncryptNotes/Views/Mac/StickyNoteWindow.swift
EncryptNotes/Views/Mac/StickyNoteEditorView.swift
EncryptNotes/Views/Mac/LockedStickyNoteView.swift
```

### 数据结构建议

```swift
struct MacWindowFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct MacNoteWindowState: Codable, Equatable {
    var noteId: String
    var isPinned: Bool
    var frame: MacWindowFrame
    var lastOpenedAt: Date
}
```

### 持久化建议

- v0.1 窗口位置/尺寸可先保存在本机 `UserDefaults`。
- 不建议写入 iCloud note 文件，避免移动端 schema 变复杂。
- key 示例：`mac.windowState.<note_id>`。

### 窗口规则

- 新建后立即进入编辑状态。
- 默认 Pin，窗口层级高于普通应用窗口。
- 用户可以取消 Pin / 重新 Pin。
- 关闭窗口只隐藏，不删除。
- 再次打开恢复上次窗口尺寸和位置。
- 默认在当前活跃 Desktop 出现。
- v0.1 不做所有 Desktop 显示。

### 验收

- 每条笔记有独立窗口。
- Pin 状态窗口在普通应用窗口之上。
- 取消 Pin 后恢复普通层级。
- 关闭不删除文件。
- 重新打开恢复尺寸和位置。

---

## 4.4 编辑器与自动保存模块

### 目标

使用 macOS 原生文本编辑能力，优先保证中文输入稳定。

### 文件建议

```text
EncryptNotes/Views/Mac/StickyNoteEditorView.swift
EncryptNotes/Stores/MacEditorAutosaveStore.swift
```

### 实现建议

- 优先使用 `NSTextView` 包装，而不是纯 SwiftUI `TextEditor`，以确保中文输入法候选框跟随光标。
- 通过 `NSViewRepresentable` 封装 `NSTextView`。
- 保存纯文本，不保存富文本。
- 支持复制、粘贴、撤销、重做。

### 自动保存规则

- 输入停止约 500ms 后保存。
- 窗口失去焦点时立即保存。
- 窗口关闭前立即保存。
- 保存失败显示非阻塞错误提示。
- 不提供手动保存按钮。

### 验收

- 简体中文输入法候选框正确跟随光标。
- 拼音组合输入不丢字、不重复上屏。
- 回车提交候选与换行行为正常。
- 中英文混合输入正常。
- 自动保存不会频繁卡顿。
- 关闭窗口前最新内容不丢失。

---

## 4.5 明文笔记模块

### 目标

支持新建、编辑、保存、打开、删除、恢复明文便利贴。

### 复用

- 复用现有 `PlainNoteFile`。
- 复用现有 `PlainNoteFile.body` 作为正文落盘字段，不新增 `content` 字段。
- 复用现有 `vault_id` 与回收站元数据字段，保证 iOS/macOS 对同一文件的读写一致。
- 复用 `.bkwplain.json` 后缀。
- 复用 `VaultStorage` 的 `plainNoteFileURL`、`listPlainNoteFiles`、`loadPlainNoteFile`、`savePlainNoteFile`。

### UI 要求

- 便利贴中明确显示“明文”状态。
- 不让用户误以为明文内容已加密。

### 验收

- 新建后 iCloud `notes/` 中生成 `.bkwplain.json`。
- 文件可被文本工具读取。
- 明文 JSON 使用现有跨端 schema，正文位于 `body` 字段。
- 编辑后 `updated_at` 更新。
- 菜单最近笔记可显示第一行非空文本。

---

## 4.6 加密笔记模块

### 目标

支持新建、编辑、保存、打开、删除、恢复加密便利贴。

### 复用

- 复用移动端 `CryptoService`。
- 复用 `VaultKeyManager`。
- 复用 `KeychainStore`，必要时做 macOS 兼容调整。
- 复用 `EncryptedNoteFile`。
- 复用 `.bkwenc.json` 后缀。

### 新建规则

```text
用户选择“新建加密笔记”
→ 检查本机是否已加载密钥
→ 已加载：创建加密便利贴
→ 未加载：不创建笔记，提示“加载密钥后才能创建加密笔记”
```

### 首次创建加密空间

如果 iCloud 中不存在 `vault.json`：

```text
首次新建加密笔记
→ 引导创建加密空间
→ 本机生成新密钥
→ 要求用户导出并保存 .bkwkey
→ 用户确认已保存
→ 才允许创建第一条加密笔记
```

### 锁定状态

- 未加载密钥时，加密笔记显示锁定窗口。
- 不允许查看或编辑正文。
- 提供“加载密钥文件”按钮。
- 允许移入回收站，但需要二次确认。

锁定文案：

```text
这台 Mac 还没有当前加密空间的密钥。
加载密钥文件后，笔记将在本机解密显示。
```

### 验收

- `.bkwenc.json` 中不得出现正文、标题、预览、摘要明文。
- 未加载密钥不能查看或编辑。
- 错误密钥不能解锁。
- 正确密钥可查看和编辑。
- 编辑后重新加密再写入 iCloud。
- 移除本机密钥后立即回到锁定状态。

---

## 4.7 密钥加载与移除模块

### 目标

支持加载 `.bkwkey`、保存到本机 Keychain、移除本机密钥。

### 文件建议

```text
EncryptNotes/Views/Mac/KeyFileImportView.swift
EncryptNotes/Views/Mac/KeyFileExportView.swift
```

### 加载流程

```text
用户选择“加载密钥文件”
→ 系统文件选择器打开
→ 用户选择 .bkwkey 文件
→ App 本机读取并校验密钥
→ 校验成功后解密当前加密空间笔记
→ 保存到本机 Keychain
```

### 文案

```text
密钥文件只会在本机读取，不会上传。
```

错误密钥提示：

```text
无法使用这个密钥解锁当前加密空间。
```

### 验收

- `.bkwkey` 可以通过系统文件选择器加载。
- 成功后加密笔记解锁。
- 错误密钥不展示明文，不改文件。
- 移除本机密钥后所有加密笔记立即锁定。
- 密钥不写入 iCloud Drive。

---

## 4.8 全部笔记列表模块

### 目标

提供基础笔记列表，避免超过最近 8 条后无法找回旧笔记。

### 文件建议

```text
EncryptNotes/Views/Mac/AllNotesWindow.swift
EncryptNotes/Views/Mac/AllNotesListView.swift
```

### 功能范围

- 查看全部笔记。
- 按最近更新时间排序。
- 打开笔记。
- 删除笔记。
- 复用现有正文搜索。
- 复用现有正文 `#tag` 解析与标签筛选。
- 不支持分组和批量操作。

### 显示规则

- 明文笔记显示第一行非空文本。
- 已解锁加密笔记显示解密后的第一行。
- 未解锁加密笔记显示：`加密笔记 · 未加载密钥`。
- 未解锁状态不得生成明文预览缓存。

### 验收

- 超过 8 条之外的旧笔记可从全部列表打开。
- 排序正确。
- 正文搜索可过滤明文笔记与已解锁加密笔记。
- `#tag` 筛选可过滤明文笔记与已解锁加密笔记。
- 未解锁加密笔记不参与搜索和标签筛选，也不得生成明文预览缓存。
- 删除后文件进入 `trash/`。

---

## 4.9 回收站模块

### 目标

支持查看、恢复、永久删除、清空回收站。

### 文件建议

```text
EncryptNotes/Views/Mac/TrashWindow.swift
EncryptNotes/Views/Mac/TrashListView.swift
```

### 规则

- 删除笔记时移动到 iCloud `trash/`，不直接永久删除。
- 删除后对应便利贴窗口关闭。
- 恢复时移回 `notes/`。
- 永久删除时从 `trash/` 删除文件。
- 清空回收站删除 `trash/` 下所有笔记文件。
- 删除时写入 `deleted_at` 与 `purge_after`，复用现有自动清理期限。
- 超过 `purge_after` 的回收站文件允许在启动、回到前台或后续维护任务中自动永久删除。
- 未加载密钥时，加密笔记只显示锁定占位，不显示正文预览。

### 验收

- 删除后文件移动到 `trash/`。
- 恢复后文件移回 `notes/`。
- 永久删除后文件消失。
- 清空回收站可用。
- 超过自动清理期限的回收站文件会被自动永久删除。

---

## 4.10 iCloud 同步与冲突模块

### 目标

确保 macOS 端与 iOS 端共享同一套 iCloud 文件协议。

### 同步状态

v0.1 只显示：

- 已保存
- 正在同步
- 同步失败

### 冲突规则

多设备同时修改同一笔记时：

- 不允许静默丢失内容。
- 保留更新时间较新的原笔记。
- 将另一份保存为新的冲突副本。
- 冲突副本通过文件名追加 `-conflict-<timestamp>` 区分，内部 `note_id` 可以沿用原文件。

### 实现建议

- 保存前读取磁盘上的当前文件，比较 `updated_at`。
- 若磁盘版本更新，生成冲突副本。
- 冲突副本可以直接复制原文件，再改文件名。
- 全部笔记和窗口管理不要只依赖内部 `note_id` 去重；展示冲突副本时可使用文件 URL 或 `note_id + filename` 作为 UI identity。

### 验收

- 离线编辑后恢复联网可继续同步。
- 其他设备可看到新增/修改文件。
- 并行编辑不会静默覆盖。
- 冲突副本可在全部笔记中看到，即使内部 `note_id` 与原文件相同。

---

## 5. Store / 状态管理建议

### 5.1 复用现有 VaultStore

`VaultStore` 继续作为核心状态源，负责：

- 初始化 vault。
- 加载 manifest。
- 加载明文/加密笔记。
- 创建/更新/删除/恢复笔记。
- 密钥导入/移除。
- 解密状态管理。
- 默认示例笔记、正文搜索、正文 `#tag` 解析与标签筛选状态。
- 回收站自动清理。

### 5.2 新增 macOS 专属 Store

建议新增：

```text
MacNoteWindowStore
ShortcutStore
SyncStatusStore
MacSettingsStore
```

职责：

- `MacNoteWindowStore`：打开/聚焦/关闭便利贴窗口，保存窗口 frame 与 pin 状态。
- `ShortcutStore`：注册、注销、修改全局快捷键。
- `SyncStatusStore`：维护当前保存/同步失败提示。
- `MacSettingsStore`：保存 macOS 专属设置。

---

## 6. 测试计划

### 6.1 单元测试

新增或复用测试覆盖：

- 明文笔记 `.bkwplain.json` 编解码。
- 明文笔记使用现有 `PlainNoteFile.body` 字段，不新增 `content` 字段。
- 加密笔记 `.bkwenc.json` 编解码。
- 加密 JSON 不包含正文原文。
- 正确 key 解密成功。
- 错误 key 解密失败。
- 未加载 key 时不生成预览。
- 正文搜索只作用于明文笔记和已解锁加密笔记。
- `#tag` 筛选只作用于明文笔记和已解锁加密笔记。
- 文件后缀过滤。
- 删除进入 `trash/`。
- 恢复移回 `notes/`。
- 超过 `purge_after` 的回收站文件会被自动清理。
- 冲突副本通过 `-conflict-<timestamp>` 文件名生成，内部 `note_id` 可以沿用原值。

### 6.2 macOS UI/集成测试清单

- 菜单栏入口存在。
- Dock 图标默认隐藏。
- 菜单新建明文笔记成功。
- 菜单新建加密笔记成功。
- 全局快捷键新建成功。
- 新窗口获得焦点。
- Pin / 取消 Pin 生效。
- 关闭窗口不删除文件。
- 重新打开恢复尺寸和位置。
- 中文输入法输入稳定。
- 自动保存 500ms debounce 生效。
- 失焦/关闭立即保存。
- 错误密钥无法解锁。
- 移除密钥后立即锁定。
- 回收站恢复/永久删除/清空正常。
- 回收站自动清理行为正常。

### 6.3 推荐命令

```bash
# iOS 现有构建
xcodebuild -project EncryptNotes.xcodeproj -scheme EncryptNotes \
  -destination 'generic/platform=iOS Simulator' build

# macOS 构建，新增 scheme 后使用
xcodebuild -project EncryptNotes.xcodeproj -scheme EncryptNotesMac \
  -destination 'platform=macOS' build

# iOS 单元测试
xcodebuild -project EncryptNotes.xcodeproj -scheme EncryptNotes \
  -destination 'platform=iOS Simulator,name=iPhone 15' test

# macOS 测试，新增 test target/scheme 后使用
xcodebuild -project EncryptNotes.xcodeproj -scheme EncryptNotesMac \
  -destination 'platform=macOS' test
```

---

## 7. 分阶段实施计划

## Phase 0：工程探查与准备

### 目标

确认现有代码能被 macOS target 复用的范围，列出需要条件编译的点。

### 任务

- 检查 `Models/Crypto/Storage/Utils` 是否包含 UIKit-only API。
- 检查 `Stores` 是否包含 iOS-only scenePhase / UIApplication API。
- 检查 `KeychainStore` 在 macOS sandbox 下是否可用。
- 检查 iCloud container entitlement 配置。
- 检查 StoreKit/付费逻辑是否需要从 macOS v0.1 中排除。
- 确认 macOS 继续使用现有 `PlainNoteFile.body` schema，不引入 `content` 字段。
- 确认默认示例笔记、正文搜索、正文 `#tag` 解析和标签筛选在 macOS target 中可复用。

### 交付物

- 兼容性问题清单。
- macOS target 文件 membership 清单。

---

## Phase 1：新增 macOS target 与最小菜单栏 App

### 目标

App 能在 macOS 启动，菜单栏出现入口，默认不显示 Dock 图标。

### 任务

- 新增 `EncryptNotesMac` target。
- 新增 `EncryptNotesMac.entitlements`。
- 配置 iCloud container。
- 新增 macOS App 入口。
- 实现菜单栏基础菜单。
- 初始化 `VaultStore`。

### 验收

- macOS build 通过。
- 启动后菜单栏有图标。
- 默认不显示 Dock 图标。
- 菜单中能看到 v0.1 入口项。

---

## Phase 2：明文便利贴闭环

### 目标

完成明文笔记从新建、编辑、自动保存、打开、删除到回收站的闭环。

### 任务

- 实现明文便利贴窗口。
- 实现 `NSTextView` 编辑器封装。
- 实现 500ms debounce 自动保存。
- 实现失焦/关闭立即保存。
- 实现窗口 Pin / 取消 Pin。
- 实现窗口位置尺寸本机保存。
- 实现最近 8 条菜单展示。
- 实现全部笔记基础列表。
- 实现或接入正文搜索与 `#tag` 筛选。
- 实现删除到回收站。

### 验收

- 新建明文笔记生成 `.bkwplain.json`。
- 明文状态明确展示。
- 中文输入稳定。
- 自动保存生效。
- 最近笔记可打开聚焦。
- 全部列表可打开超过 8 条之外的笔记。
- 正文搜索和 `#tag` 筛选可用于可读笔记。
- 删除后进入 `trash/`。

---

## Phase 3：密钥与加密便利贴闭环

### 目标

完成加密笔记的新建、锁定、加载密钥、编辑、重新加密、移除密钥闭环。

### 任务

- 实现加载 `.bkwkey` 文件。
- 实现错误密钥提示。
- 实现移除本机密钥。
- 实现首次创建加密空间流程。
- 实现加密便利贴窗口。
- 实现未加载密钥锁定窗口。
- 实现加密笔记菜单/列表占位展示。
- 确保加密 JSON 不包含明文。

### 验收

- 未加载密钥时不能创建加密笔记，除首次创建加密空间引导外。
- 锁定加密笔记不能查看/编辑正文。
- 正确密钥解锁后可编辑。
- 编辑后写入 `.bkwenc.json`。
- 错误密钥不能展示明文。
- 移除密钥后立即锁定。

---

## Phase 4：回收站与恢复

### 目标

完成回收站的查看、恢复、永久删除、清空。

### 任务

- 实现回收站窗口。
- 列出 `trash/` 下明文与加密笔记。
- 恢复到 `notes/`。
- 永久删除文件。
- 清空回收站。
- 复用并验证基于 `purge_after` 的自动清理。
- 锁定加密笔记只显示占位。

### 验收

- 删除文件移动到 `trash/`。
- 恢复后文件回到 `notes/`。
- 永久删除后文件消失。
- 清空回收站正常。
- 超过自动清理期限的文件会被自动永久删除。
- 未加载密钥时回收站不泄露加密正文。

---

## Phase 5：同步状态、冲突处理与收尾

### 目标

补齐同步状态提示和冲突不丢失机制，达到 v0.1 验收标准。

### 任务

- 显示已保存/正在同步/同步失败。
- 保存失败显示非阻塞错误。
- 保存前比较磁盘 `updated_at`。
- 冲突时复制原文件并生成带 `-conflict-<timestamp>` 的冲突副本文件名。
- 确保全部笔记和窗口管理能展示内部 `note_id` 相同的冲突副本。
- 补齐单元测试和集成测试。
- 整理文案，确保使用“加载密钥文件”。
- 检查不做项没有误实现。

### 验收

- 同步状态可见。
- 并行编辑不静默覆盖。
- 冲突副本文件名包含 `-conflict-<timestamp>`。
- 内部 `note_id` 相同的冲突副本仍可在全部笔记中看到。
- 加密文件无明文泄漏。
- 全部 v0.1 验收清单通过。

---

## 8. 关键实现细节提示

### 8.1 菜单栏实现选择

优先级：

1. 如果 `MenuBarExtra` 能满足最近笔记动态菜单和退出逻辑，优先用 SwiftUI `MenuBarExtra`。
2. 如果需要更强控制菜单项、快捷键展示、NSWindow 聚焦，使用 `NSStatusItem + NSMenu`。

v0.1 推荐 `NSStatusItem + NSMenu`，因为更适合复杂菜单与窗口聚焦。

### 8.2 文本编辑器实现选择

优先使用 `NSTextView` 包装：

- 中文输入法稳定性更高。
- Undo/Redo 支持更自然。
- 候选框跟随光标更可控。

### 8.3 Pin 实现建议

- Pin：`NSWindow.Level.floating`。
- 取消 Pin：`NSWindow.Level.normal`。
- v0.1 不设置 `canJoinAllSpaces`，避免误实现 P1 的“所有 Desktop 显示”。

### 8.4 Dock 隐藏

可选方案：

- Info.plist 设置 `LSUIElement = YES`。
- 或启动时：`NSApp.setActivationPolicy(.accessory)`。

若需要设置窗口获得焦点，创建/打开窗口时可临时调用：

```swift
NSApp.activate(ignoringOtherApps: true)
window.makeKeyAndOrderFront(nil)
```

### 8.5 同步状态说明

严格来说 iCloud 文件同步状态不一定能精确反映上传完成。v0.1 可以采用务实定义：

- 本地写入中：正在同步。
- 本地写入成功：已保存。
- 本地写入失败：同步失败。

不要承诺精确的远端上传完成状态。

---

## 9. 给后续模型的执行提示

1. 先读：
   - `AGENTS.md`
   - `别看我_macOS_PRD_v0.1.md`
   - `EncryptNotes/Storage/VaultStorage.swift`
   - `EncryptNotes/Storage/ICloudVaultStorage.swift`
   - `EncryptNotes/Stores/VaultStore.swift`
   - `EncryptNotes/Crypto/CryptoService.swift`
   - `EncryptNotes/Crypto/KeychainStore.swift`
2. 不要改变 iCloud 文件后缀和目录结构。
3. 不要把加密笔记正文、预览、摘要、标签、搜索索引写到外层 JSON。
4. macOS UI 可以重新做，但数据层尽量复用现有实现。
5. 每个阶段尽量小 PR：工程 target、明文闭环、加密闭环、回收站、冲突/测试。
6. 对 schema、加密、安全约束的改动必须补测试。
7. 除本计划 1.4 已确认取舍外，PRD 明确不做的功能不要顺手实现。

---

## 10. v0.1 最终验收清单

### 菜单栏与快捷键

- [ ] App 启动后菜单栏显示入口。
- [ ] 默认不显示 Dock 图标。
- [ ] 菜单栏可新建明文笔记。
- [ ] 菜单栏可新建加密笔记。
- [ ] 全局快捷键可新建明文笔记。
- [ ] 全局快捷键可新建加密笔记。
- [ ] 最近笔记最多显示 8 条。
- [ ] 最近笔记按更新时间倒序。
- [ ] 明文笔记在最近笔记中显示第一行非空文本。
- [ ] 已解锁加密笔记在最近笔记中显示解密后的第一行。
- [ ] 未加载密钥的加密笔记在最近笔记中只显示“加密笔记 · 未加载密钥”。
- [ ] 最近笔记不会为未解锁加密笔记生成明文预览缓存。
- [ ] 点击最近笔记可打开并聚焦。
- [ ] 全部笔记可打开最近 8 条之外的旧笔记。
- [ ] 全部笔记支持正文搜索可读笔记。
- [ ] 全部笔记支持正文 `#tag` 筛选可读笔记。

### 便利贴窗口

- [ ] 每条打开笔记对应独立窗口。
- [ ] 新建窗口立即获得输入焦点。
- [ ] 新建笔记默认 Pin。
- [ ] Pin 状态位于普通应用窗口之上。
- [ ] 可取消 Pin / 重新 Pin。
- [ ] 关闭窗口不删除笔记。
- [ ] 再次打开恢复窗口尺寸和位置。
- [ ] v0.1 不承诺所有 Desktop 显示。

### 编辑器与自动保存

- [ ] 简体中文输入候选框跟随光标。
- [ ] 拼音组合输入不丢字、不重复上屏。
- [ ] 回车提交候选和换行行为正常。
- [ ] 中英文混输正常。
- [ ] 复制、粘贴、撤销、重做正常。
- [ ] 输入停止约 500ms 后保存。
- [ ] 失焦或关闭窗口立即保存。
- [ ] 保存失败显示非阻塞错误。

### 明文与加密

- [ ] 明文笔记保存为 `.bkwplain.json`。
- [ ] 明文 JSON 使用现有 `PlainNoteFile.body` 字段，不新增 `content` 字段。
- [ ] 明文文件可被普通文本工具读取。
- [ ] App 明确显示“明文”状态。
- [ ] 加密笔记保存为 `.bkwenc.json`。
- [ ] 加密 JSON 不包含正文、标题、预览、摘要、标签、搜索索引。
- [ ] 未加载密钥时不能查看或编辑加密正文。
- [ ] 错误密钥不能解密笔记。
- [ ] 正确密钥可查看和编辑。
- [ ] 编辑后的加密笔记重新加密后写入 iCloud。
- [ ] 移除本机密钥后立即恢复锁定。
- [ ] 密钥文件和密钥内容不写入 iCloud Drive。

### iCloud 与回收站

- [ ] 新建笔记后 iCloud 中生成对应文件。
- [ ] 修改笔记后对应文件更新。
- [ ] 离线编辑后恢复联网可继续同步。
- [ ] 其他同 Apple ID 设备可看到新增或修改文件。
- [ ] 并行编辑冲突不会静默丢失内容。
- [ ] 冲突副本通过 `-conflict-<timestamp>` 文件名生成。
- [ ] 内部 `note_id` 相同的冲突副本仍可在全部笔记中看到。
- [ ] 删除笔记后文件移动到 `trash/`。
- [ ] 可恢复删除的笔记。
- [ ] 可永久删除单条笔记。
- [ ] 可清空回收站。
- [ ] 超过 `purge_after` 的回收站文件会被自动永久删除。
- [ ] 未加载密钥时仍可删除/恢复加密文件，但不能查看正文。
