# Seal Note 隐私政策

生效日期：2026 年 7 月 20 日

Seal Note 尊重并保护你的隐私。本政策说明 Seal Note 如何处理你的信息。

## 我们处理的信息

Seal Note 不要求注册账户，不包含广告、用户追踪或第三方分析 SDK，开发者不会通过本应用收集、出售或共享你的个人信息、笔记内容或使用行为。

应用会在你的设备上处理以下信息，以提供核心功能：

- 你创建的笔记、笔记元数据和废纸篓信息；
- 你选择的应用设置、窗口状态和快捷键；
- 由你创建或导入、并由你自行管理的加密密钥文件或本机密钥引用；
- 仅在你主动开启“维护日志”后生成的本地诊断记录。维护日志只记录保存、索引等运行元数据，不记录笔记正文或加密密钥。

## 存储、同步与加密

笔记优先保存在你的 Apple iCloud Drive 容器中，以便在登录同一 Apple Account 的设备间同步；iCloud 不可用时，笔记保存在设备本地。iCloud 数据由 Apple 按照 Apple 的条款和隐私政策处理，开发者无法访问你的 iCloud Drive 内容。

使用加密笔记时，笔记正文会在设备端使用 AES-GCM 加密后再写入存储。用于文件识别和同步的部分元数据（例如笔记标识符和时间戳）不会加密。明文笔记不会加密。

## 数据保留与删除

数据会一直保留在你的设备或 iCloud Drive 中，直到你在应用内删除、清空废纸篓，或通过 Finder/iCloud Drive 删除相关文件。你也可以在系统设置中停用 Seal Note 的 iCloud 权限，或关闭 iCloud Drive 同步。卸载应用可能不会自动删除已保存在 iCloud Drive 中的文件。

维护日志默认关闭，并仅保存在本机。你可以随时关闭日志记录，并在应用显示的日志文件夹中删除日志文件。只有当你主动导出并分享日志时，接收方才能获得该文件。

## 第三方与数据披露

除用于文件同步的 Apple iCloud 服务外，Seal Note 不会将上述数据发送给开发者或第三方。若法律要求披露信息，开发者只能披露其实际持有的信息；由于开发者无法访问你的设备或 iCloud Drive 内容，通常没有可供披露的笔记数据。

## 可选命令行访问

macOS 版本提供默认关闭的本机命令行接口。只有你在设置中明确启用后，随 App 签名分发的 `sealnote` 工具才能通过 `127.0.0.1` 上的认证通道请求 Seal Note 读取、搜索、创建、修改明文笔记或将明文笔记移入废纸篓。CLI 不直接读取保险库文件或密钥，也不会把内容发送给开发者。

CLI 不会返回加密笔记的标题、标识符、数量或正文，也不能创建或修改加密笔记。每次 App 启动都会生成新的本机会话令牌；关闭 CLI 或退出 Seal Note 后令牌失效。你应只向可信工具开放，并在不使用时关闭。

## 儿童隐私

Seal Note 不会有意收集儿童的个人信息，也不面向儿童进行行为追踪或广告投放。

## 政策变更

如果应用的数据处理方式发生变化，本政策将同步更新，并修改页面顶部的生效日期。重大变化会在适当情况下通过应用更新说明告知用户。

## 联系我们

如对本政策、数据删除或隐私选择有疑问，请通过 [GitHub Issues](https://github.com/XuWeinan123/EncryptNotes_for_TRAE/issues) 联系开发者。请勿在公开 Issue 中提交笔记正文、密钥或其他敏感信息。

---

# Seal Note Privacy Policy

Effective date: July 20, 2026

Seal Note does not require an account and contains no advertising, user tracking, or third-party analytics SDKs. The developer does not collect, sell, or share your personal information, note content, or usage activity through the app.

Your notes, note metadata, settings, window state, shortcuts, and user-managed encryption key file or local key reference are processed on your device to provide the app's features. Optional maintenance logs are disabled by default, remain on your device, and record operational metadata only—not note content or encryption keys.

Notes are stored in your Apple iCloud Drive container when available so they can sync between devices signed in to the same Apple Account; otherwise, they are stored locally. Apple processes iCloud data under its own terms and privacy policy, and the developer cannot access your iCloud Drive content. Encrypted-note bodies are encrypted on device using AES-GCM before storage. Metadata needed for file identification and synchronization, such as note identifiers and timestamps, is not encrypted. Plain notes are not encrypted.

Data remains on your device or in iCloud Drive until you delete it in the app, empty the trash, or remove the files through Finder or iCloud Drive. You can disable Seal Note's iCloud access or iCloud Drive syncing in system settings. Uninstalling the app may not remove files stored in iCloud Drive. You can disable maintenance logging at any time and delete its local log file from the folder shown by the app. A third party receives a log only if you intentionally export and share it.

Other than Apple iCloud for file synchronization, Seal Note does not transmit this data to the developer or third parties. Seal Note does not knowingly collect children's personal information. If the app's data practices change, this policy and its effective date will be updated.

The macOS app includes an optional local command-line interface that is disabled by default. Once explicitly enabled in Settings, the signed `sealnote` helper communicates with the running app over an authenticated `127.0.0.1` connection. It does not directly access vault files or encryption keys and does not send note content to the developer. Encrypted-note titles, identifiers, counts, and bodies are hidden from the CLI, which cannot create or modify encrypted notes. Session credentials rotate whenever the app starts and are revoked when CLI access is disabled or the app exits.

For privacy questions, deletion guidance, or privacy choices, contact the developer through [GitHub Issues](https://github.com/XuWeinan123/EncryptNotes_for_TRAE/issues). Do not include note content, encryption keys, or other sensitive information in a public issue.
