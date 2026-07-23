# Seal Note iOS 稳定化说明 / iOS Stabilization Notes

本文档记录 iOS 端稳定化（阶段 0–12）所做的改动、测试方法与需人工验证的清单，并汇总加密与数据相关的用户须知。macOS 端不受本轮影响（共享代码保持双平台可编译）。

---

## 一、改了什么（按缺陷）

### P0（可能丢笔记或丢密钥）

- **保险库身份稳定（P0-1）。** 新增 `Stores/VaultIdentityStore.swift`：以 `<容器>/.meta/vault.json` 为权威身份来源，UserDefaults(`SNVaultId`) 仅作缓存。`initialize()` 不再每次冷启动新造 UUID；`createKey`/`importKeyFile` 现在要求已解析的 `vaultId`（缺失则报错，绝不新造）。支持从旧 Keychain 账户「领养」身份（仅当能解密现有加密笔记时）；`vault.json` 与缓存/Keychain 冲突时以 `vault.json` 为准并把 Keychain 密钥迁移到该 id。"保存密钥"提醒改为持久化（`SNNeedsKeyExportPending`），导出成功前不会丢。
- **云端占位安全（P0-2）。** 未下载完成的 iCloud 明文笔记正文为空但被标记为 `cloudOnlyPlainNoteIDs`。清空空白笔记、导出 ZIP、批量复制、主页"空笔记"计数现在都会跳过这些占位笔记，避免误删或导出空白。
- **存储根锁定（P0-3）。** 新增 `SettingsStore.pinnedStorageRoot`（`SNPinnedStorageRoot`）。`resolveStorage(pinned:iCloudAvailable:)` 锁定存储根：iCloud 短暂不可用时临时用本机但**不改锁定**并提示不一致；用户改用本机后 iCloud 恢复也不会自动切回。检测到本机遗留笔记时，主页弹窗与"设置→同步"提供**合并到 iCloud**（复制—校验—删除，重名保留为「本机副本」）。
- **串行写入 + 可见冲突（P0/P1-2）。** 新增 `actor VaultFileIO` 把磁盘写入移出主线程并串行化，避免并发写交叉。`ICloudVaultStorage.atomicWrite` 由「删原文件再移动」改为 `FileManager.replaceItemAt`（消除文件短暂缺失窗口）。保存冲突不再被静默覆盖到隐藏的 `conflicts/`，而是生成一条**可见的**「（冲突副本 …）」笔记，进入正常列表与搜索。
- **隐私遮罩 + 非破坏性会话锁（P0-4）。** 新增窗口级 `PrivacyShieldWindowController`，遮罩覆盖到所有已弹出的 sheet（App 切换器快照不再泄露）。原来「回到前台自动移除本机密钥」的**破坏性**逻辑已删除；改为非破坏性的 `lockSession()`/`unlockSession()`（只清内存密钥、Keychain 不动，回前台用 Face ID / 密码重新解锁）。新增开关「离开 App 后锁定加密笔记」（`SNLockSessionOnBackground`，默认关）。
- **可靠防抖自动保存（P0-5）。** 新增 `EditorSession`：防抖保存（编辑即存，防止被系统杀进程丢失）、单个在途保存且始终以最新修订版本收敛（不再因 `guard !isSaving` 丢并发保存）、幂等 `close()`、模式转换不再关闭编辑器。后台切换时在 `beginBackgroundTask` 内 flush。

### P1

- **编辑器性能 + 查找（P1-1）。** 编辑器 `UITextView` 改为自滚动（去掉 `sizeThatFits` 与外层 `ScrollView`）。增量高亮 `applyIOSHighlighting(dirtyRange:)` 只对改动段落重算属性，长文档降级防抖；中文拼音（`markedTextRange`）保护逻辑原样保留。`isFindInteractionEnabled` 开启系统查找。

### 阶段 9–10 重构与精修

- **符号更名（阶段 9a，键名冻结）。** 共享符号去掉 Mac 前缀：`macEditorFontSize`→`editorFontSize`、`macEditorLineHeightMultiple`→`editorLineHeightMultiple`、`MacTheme`→`AppTheme`、`macTheme`→`appTheme`、`MacMarkdownFormatter`/`MacMarkdownHighlighter`→`MarkdownFormatter`/`MarkdownHighlighter`（两文件移到 `Views/Markdown/`）。**UserDefaults 键（`SNMacEditorFontSize`/`SNMacTheme` 等）原样保留**，零数据迁移。修正 `DesignSystem.swift` 里硬编码的 `"SNMacTheme"` 字面量，改用共享常量。
- **删除死代码（阶段 9b）。** 删除零引用的 `Views/SidebarView.swift` 及其 pbxproj 例外条目。
- **搜索精修（阶段 10a）。** 删除假的「语音搜索」麦克风按钮、重复的自定义底部搜索框（改为只保留系统 `.searchable` + 底部新建笔记按钮）、以及导航时清空搜索词的反模式。修正夹带英文「N selected」→「已选 N 条」。

---

## 二、测试与验证

```bash
cd /Users/wally/Documents/EncryptNotes_for_TRAE
./script/verify.sh ios-build      # iOS 构建
./script/verify.sh mac-build      # macOS 构建（共享代码必须保持可编译）
./script/verify.sh mac-test       # SealNoteMacTests（CLICommandServiceTests）
./script/verify.sh ios-test       # SealNoteTests
```

注意事项（`script/verify.sh` 已封装 `DEVELOPER_DIR=Xcode-beta`、模拟器发现与预启动）：

- **两个既有（豁免）失败**：`SettingsStoreTests.testRecentNotesLimitIsClamped` 与 `testRecentNotesLimitPersists` 在本轮之前即失败，因此 `ios-test` 恒退出 65。验收标准是「相对基线无新增失败」——请比对失败**列表**而非退出码。
- **串联顺序**：`ios-test` 恒非零，`&&` 串联时必须把 `mac-test` 放在 `ios-test` **之前**，否则永远跑不到 mac-test。
- **测试包偶发不重建**：改测试文件后若新测试没跑到，删除 `~/Library/Developer/Xcode/DerivedData/SealNote-*/Build/Products/*/SealNoteTests.xctest` 再跑。

新增单元测试（均通过）：保险库身份 5、云端占位 2、存储根 3、串行写入/冲突 2、会话锁 2、EditorSession 5、增量高亮 2。

---

## 三、需人工验证（无法在无 UI 自动化下确认）

- App 切换器快照：在打开的编辑器 sheet 上仍被遮罩覆盖。
- 中文拼音在编辑器内输入不被打断；系统查找可用。
- 开启「离开 App 后锁定加密笔记」后，回前台弹出 Face ID / 密码；解锁后加密笔记恢复。
- 冷启动后加密笔记能用原密钥解密（P0-1 回归）。
- iCloud 退出/重新登录不再静默分叉；本机遗留笔记的合并弹窗与设置入口可用。
- 保存冲突时生成「（冲突副本 …）」笔记且原笔记保留内存版本。
- 搜索：无麦克风按钮；搜索词在列表导航间保持；系统 `.searchable` 正常。

---

## 四、加密与数据须知（面向用户）

- **加密范围**：仅笔记正文以 AES-256 加密（`snenc:v1:` 前缀）。文件名/标题、创建与修改时间等元数据不加密。详见 `PRIVACY.md`。
- **密钥备份**：密钥存于本机 Keychain，**不随 iCloud 同步**。请通过"导出密钥（.snkey）"备份；在另一台设备或重装后需导入同一密钥才能解密。
- **iCloud / 本机存储**：默认优先 iCloud Drive；iCloud 不可用时临时使用本机并提示。用户可查看当前存储根；发现本机遗留笔记时可一键合并到 iCloud。
- **冲突副本**：多设备同时编辑同一笔记且内容不同时，磁盘上较新的版本会保留为一条独立的「（冲突副本 …）」笔记，不会被静默覆盖。
- **移除本机密钥的后果**：移除后本机无法解密加密笔记，直到重新导入密钥；此操作有二次确认。会话锁（离开 App 后锁定）不会删除密钥，只需重新验证即可恢复。

---

## 五、本轮未做（明确推迟）

- 阶段 9 的 `environmentObject` 依赖注入、路由枚举合并、View 拆分（纯代码组织、无用户可见价值，且 DI 改动在无 UI 冒烟测试的无人值守环境下有运行期崩溃风险）。当前 `X.shared` 单例访问工作正常。
- 阶段 10b 设置信息架构（存储与恢复 / 诊断 分区、密钥危险区分离）、10c 编辑器保存状态行 / 转换 toast、以及阶段 11 iPad `NavigationSplitView` 自适应导航——见 `README` 与最终报告中的状态。
- String Catalog 全量国际化、App Intents / Widgets / Spotlight、XCUITest、存储根手动切换器、iPad 三栏、iPhone 横屏（均为产品决策或需新建 target，非稳定化任务）。
