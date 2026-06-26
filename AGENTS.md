# AGENTS.md

本文件为 AI 代理（Trae / Claude / Cursor 等）在本仓库中工作时的指引。最后更新基于 v0.1 代码现状。

## 项目概述

《别看我》（EncryptNotes / Seal Notes）是一个 iPhone 优先的加密卡片笔记 App。核心闭环：用户在本地用 AES-GCM 加密笔记内容，每条笔记对应一个独立的加密 JSON 文件，通过 iCloud 同步；未导入密钥时只显示密文乱码，导入正确的 `.bkwkey` 密钥文件后在本机解密展示明文。Free 最多 20 条笔记，Pro 买断无限。

- 平台：iOS 17.0+（iPhone 优先）、macOS（菜单栏便利贴模式），SwiftUI，Swift 5.0
- Bundle ID：`com.biekanwo.EncryptNotes`
- iCloud 容器：`iCloud.com.biekanwo.EncryptNotes`
- DEVELOPMENT_TEAM：`BPP589VP97`
- TARGETED_DEVICE_FAMILY：`1,2`（iPhone 优先，iPad 兼容运行但不专门优化）
- v0.1 不做：账号系统、自建服务端、Android、Web、富文本、附件、图片、语音、多人协作、服务端搜索/备份、订阅制（PRD 明确买断，注意下方 StoreKit 配置不一致问题）。macOS 以菜单栏便利贴模式支持，不做完整多窗口笔记管理。

需求与设计依据见根目录三份文档：
- [别看我_PRD_v0.1.md](file:///workspace/别看我_PRD_v0.1.md) — 产品范围与验收标准
- [开发计划.md](file:///workspace/开发计划.md) — 模块拆分与开发顺序
- [DESIGN.md](file:///workspace/DESIGN.md) — flomo 风格设计系统

开发过程关键事件记录见 [MEMORY/](file:///workspace/MEMORY/) 目录（按日期命名），包含 macOS 版本初始化、bug 根因分析、重要架构决策等，改动相关功能前先查阅对应记录。

## 工程结构

```
EncryptNotes/
  App/EncryptNotesApp.swift        @main 入口
  ContentView.swift                直接承载 HomeView
  DesignSystem.swift               DS 枚举：颜色/字号/间距/圆角/阴影 token
  Models/                          纯数据结构（Codable）
    Note.swift                     内存中的明文笔记模型
    PlainNotePayload.swift         加密前的明文 payload（body + 时间戳）
    EncryptedNoteFile.swift        .bkwenc.json 文件 schema
    PlainNoteFile.swift            .bkwplain.json 文件 schema（未导入密钥时创建）
    VaultKey.swift                 .bkwkey 文件 schema
    VaultManifest.swift            vault.json schema
  Crypto/
    CryptoService.swift            AES-GCM 加解密（CryptoKit）
    VaultKeyManager.swift          密钥生成 / base64 / 校验
    KeychainStore.swift            密钥的 Keychain 存取
  Storage/
    VaultStorage.swift             存储协议 + URL 拼接扩展
    ICloudVaultStorage.swift       生产路径：iCloud ubiquity container
    LocalFallbackStorage.swift     模拟器/开发兜底：Documents/BieKanWo
  Stores/                          @MainActor ObservableObject 单例
    VaultStore.swift               核心状态机：noVault/locked/unlocking/unlocked/error
    PurchaseStore.swift            StoreKit 2 内购
    AppLockStore.swift             scenePhase 锁定与隐私屏
  Views/
    HomeView.swift                 三态首页外壳 + Locked/Unlocking/Unlocked 子视图
    NoteEditorView.swift           新建/编辑 sheet
    SettingsView.swift             侧滑设置面板
    ResetVaultView.swift           重置加密空间
    PaywallView.swift              Pro 升级页
    Components/
      NoteCardView.swift           明文卡片（#tag 着色）
      EncryptedCardView.swift      密文乱码卡片
      PlainNoteLockedCardView.swift 未导入密钥时的明文笔记卡片（乱码态）
      BottomComposerView.swift     底部输入框（当前未在主流程使用）
  Utils/
    JSONUtilities.swift            JSONEncoder.default / JSONDecoder.default（iso8601 + prettyPrinted + sortedKeys）
    DateFormatters.swift           ISO8601 与展示格式
    NoteObfuscator.swift           明文 → base64 截断乱码
    PressEvents.swift              按压手势修饰器
  Tests/
    CryptoServiceTests.swift       加解密往返、错 key 失败
    SchemaTests.swift              JSON 编解码、文件名过滤、乱码器
    VaultStoreTests.swift          Free 限制、明文笔记、合并排序、删除
  EncryptNotes.entitlements        iCloud Documents + ubiquity container
  EncryptNotesDebug.entitlements   空（Debug 不带 iCloud）
  Products.storekit                StoreKit 本地配置
EncryptNotes.xcodeproj/            Xcode 工程（无 Package 依赖）
```

## 架构与数据流

1. `EncryptNotesApp` → `ContentView` → `HomeView`，`HomeView` 在 `.task` 中调用 `VaultStore.shared.initialize()`。
2. `VaultStore` 是唯一的状态源（`@MainActor ObservableObject` 单例），持有 `VaultState`、`notes`、`plainNotes`、`currentKey`、`currentVaultId`。UI 通过 `@StateObject` 订阅。
3. 存储层通过 `VaultStorage` 协议抽象；`VaultStore.init` 在 iCloud 可用时选 `ICloudVaultStorage`，否则 `LocalFallbackStorage`。
4. 加密：`PlainNotePayload` → `JSONEncoder.default` → `AES.GCM.seal` → `EncryptedNoteFile`（外层 JSON 只含元数据，`payload.ciphertext/tag` 为密文）。
5. 解密：`AES.GCM.open` → `PlainNotePayload` → `Note`。错 key 抛 `authenticationFailed`，不返回任何明文。
6. 密钥生命周期：`VaultKeyManager.generateKey()` → 写 Keychain（`KeychainStore`）→ 引导用户导出 `.bkwkey`。导入时先验证能解密全部笔记，成功后才持久化到 Keychain。
7. 锁定：`AppLockStore` 监听 `scenePhase`，进后台时 `vaultStore.lock()` 清空内存明文与 key，并显示 `PrivacyScreenView` 遮罩防止系统截图泄露。

## iCloud 文件布局

```
iCloud Drive / 别看我 /
  vault.json                       VaultManifest
  notes/
    <note_id>.bkwenc.json          EncryptedNoteFile
    <note_id>.bkwplain.json        PlainNoteFile（未导入密钥时创建的明文笔记）
  trash/                           删除时优先 move 到此处，失败再 remove
  meta/
```

文件名约定不可更改：加密笔记 `.bkwenc.json`，明文笔记 `.bkwplain.json`，密钥 `.bkwkey`。`listNoteFiles()` / `listPlainNoteFiles()` 依赖后缀过滤。

## 关键约束（修改时务必遵守）

- **不得把明文 title/body/tags/摘要/搜索索引写入外层 JSON。** 这些字段只能存在于加密 `payload` 内。`PlainNotePayload` 当前只有 `body` + 时间戳，没有 title/tags 字段——不要为了方便搜索在外层补明文字段。
- **文案用「导入密钥文件」，不要写「上传密钥文件」。** 辅助说明统一为「密钥文件只会在本机读取，不会上传。」
- **错 key 必须解密失败，不得部分进入 unlocked 状态。** `importKeyFile` 先解密全部成功才写 Keychain。
- **多设备冲突不得静默覆盖。** `updateNote` 在写入前比较磁盘 `updatedAt` 与内存版本，磁盘更新时调 `createConflictCopy` 生成 `<note_id>-conflict-<timestamp>.bkwenc.json`。
- **Free/Pro 必须共用同一套加密逻辑。** Free 限制（20 条，加密 + 明文合计）由 `VaultStore.createNote` 在加密前判断并抛 `VaultError.freeLimitReached`，不能只靠 UI 禁用按钮。
- **重置加密空间必须清空 iCloud 当前 vault 文件**（`notes/`、`trash/`、`meta/`、`vault.json`），不能只清本地缓存；同时删 Keychain 旧 key 并生成新 vault_id 与新 key。
- **所有写入用原子写**（`atomicWrite` / `.atomic`），先写临时文件再替换。
- **JSON 一律走 `JSONEncoder.default` / `JSONDecoder.default`**（iso8601 日期、prettyPrinted、sortedKeys），保证多设备编码一致。
- **UI 颜色/字号/间距/圆角/阴影一律引用 `DS.*` token**，不要硬编码 hex 或字号。叶绿色 `DS.primary` 仅用于动作与标识（主按钮、`#tags`、浮动按钮）；蓝/红/紫/琥珀锁定语义角色。
- **不要引入服务端、账号系统、登录页或云数据库。**

## 已知不一致 / 待注意

- **StoreKit 配置与代码不匹配。** `Products.storekit` 定义的是月度/年度**订阅**（`com.biekanwo.encryptnotes.pro.monthly` / `.yearly`），但 `PurchaseStore` 写死 `proProductId = "pro_lifetime"` 并按**非消耗型买断**处理。PRD 要求买断制。改动付费逻辑时需同步两者，否则本地沙盒测不出购买。
- **PRD 与实现的「未导入密钥时新建笔记」分歧。** PRD 第 8 节明确「未导入密钥时不允许新建笔记」，但当前实现允许在 `.locked` 状态创建 `.bkwplain.json` 明文笔记（显示为乱码，导入密钥后转明文）。这是对 PRD 的扩展，改动前先确认产品意图。
- `BottomComposerView` 已实现但未接入主流程，首页用的是浮动 `+` 按钮 + sheet 编辑器。
- `AppLockStore` 已实现但 `HomeView` 自己又有一份 `handleScenePhaseChange` 与 `showPrivacyScreen`，两套锁定逻辑并存，注意不要重复触发。
- `EncryptNotesDebug.entitlements` 为空，Debug 构建拿不到 iCloud 容器，会自动落到 `LocalFallbackStorage`。

## 构建与测试

工程无 SPM/CocoaPods 依赖。当前本地开发与验证统一使用 Xcode beta：

- Xcode 路径：`/Applications/Xcode-beta.app/Contents/Developer`
- 运行 / 测试模拟器：优先使用 `iPhone 17`，不要默认使用 `iPhone 17 Pro` 或旧的 `iPhone 15`。
- 使用 XcodeBuildMCP 时，先设置 session defaults：project `EncryptNotes.xcodeproj`、scheme `EncryptNotes`、simulator `iPhone 17`、`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`。
- 若直接运行 `xcodebuild`，命令前加 `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`。CI 环境无 TTY，命令需非交互。

```bash
# 构建
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project EncryptNotes.xcodeproj -scheme EncryptNotes \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# 跑单元测试（EncryptNotesTests target）
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project EncryptNotes.xcodeproj -scheme EncryptNotes \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# Xcode Cloud 已配置（见 EncryptNotes.xcodeproj/xcshareddata/xcodecloud/manifest.json）
```

测试覆盖重点（与 PRD 12.x 验收对应）：
- `CryptoServiceTests`：同 key 往返成功、错 key 失败。
- `SchemaTests`：各文件 JSON 编解码稳定、`.bkwenc.json` / `.bkwplain.json` 后缀过滤、`NoteObfuscator` 输出。
- `VaultStoreTests`：Free 20 条限制（含明文笔记合计）、锁定态创建明文笔记、`filteredNotes` 合并排序、明文笔记删除落盘。

新增加密/schema/限制相关逻辑时，务必同步补测试，尤其是「密文 JSON 不含正文原文」这类安全验收点。

## 代码风格约定

- Swift，`@MainActor` 用于所有 `ObservableObject` Store。
- 单例模式：`*.shared`（`VaultStore`、`PurchaseStore`、`CryptoService`、`VaultKeyManager`、`KeychainStore`、`ICloudVaultStorage`、`LocalFallbackStorage`、`AppLockStore`）。
- 错误类型用 `enum … : Error, LocalizedError`，提供 `errorDescription`。
- Codable 的 snake_case 字段通过 `CodingKeys` 显式映射，不要全局改 key decoding 策略。
- SwiftUI 视图优先用 `DS.*` token 与 `dsCardSurface()` / `dsInputSurface()` / `dsCanvasBackground()` / `dsLiquidGlassToolbar()` 修饰器。
- Figma 设计稿是 flomo Design Library Copy：`https://www.figma.com/design/Tvq9bNPX2M0SksYFiEvaW7/flomo_%F0%9F%8D%80-Design-Library--Copy-?node-id=55349-28392&t=e1YsEKLZj2TiAOuv-4`。实现时只还原当前 App 已有功能可承载的设计元素（圆角、配色、阴影、间距、字号、卡片结构），不要为了贴设计稿新增账号、附件、图片、录音、API、插件等未实现功能。
- 设计 token 改动必须同步维护 `EncryptNotes/DesignSystem.swift` 和根目录 `DESIGN.md`，避免代码与文档漂移。
- 颜色 token 必须同时维护亮色与暗色。暗色值从 Figma Dark 组实际渲染值获取，并在 `DS` 中实现为随系统外观切换的动态 `Color`；不要只改亮色常量。
- iOS 26 及之后的 toolbar / navigation bar 使用系统组件与 `dsLiquidGlassToolbar()`，不要为了视觉相似手写仿 toolbar 背景、毛玻璃或自定义导航栏。
- 中文 UI 文案，简短第二人称；代码注释中文。
- 浮动按钮按 Figma 当前样式使用 52px、12px 圆角、轻黑色投影；不要再使用绿色光晕。

## 修改检查清单

提交前自检：
- [ ] 改动是否把任何明文内容写入了外层 JSON / iCloud 文件？
- [ ] 加密/解密路径是否对错 key 仍然安全失败？
- [ ] Free 限制是否在 `VaultStore` 后端强制，而非仅 UI 层？
- [ ] 是否引入了 PRD 明确不做的功能（账号、服务端、订阅等）？
- [ ] 新增 UI 是否全部走 `DS.*` token，未硬编码颜色/字号？
- [ ] 新增/修改 schema 是否更新了对应 `Tests/` 用例？
- [ ] 文案是否用了「导入」而非「上传」？
