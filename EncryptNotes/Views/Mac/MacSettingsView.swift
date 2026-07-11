import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MacSettingsView: View {
    enum Tab: Hashable {
        case general
        case editor
        case aiTitle
        case shortcuts
        case key
        case about
    }

    @ObservedObject private var shortcutStore = ShortcutStore.shared
    @ObservedObject private var vaultStore = VaultStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var selectedTab: Tab
    @State private var recordingAction: MacShortcutRecordingAction?
    @State private var settingsErrorMessage: String?
    @State private var deepSeekAPIKey = ""
    @State private var geminiAPIKey = ""
    @State private var apiKeyStatusMessage: String?

    init(selectedTab: Tab = .general) {
        _selectedTab = State(initialValue: selectedTab == .aiTitle ? .general : selectedTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label("通用", systemImage: "gear")
                }
                .tag(Tab.general)

            editorTab
                .tabItem {
                    Label("编辑器", systemImage: "textformat")
                }
                .tag(Tab.editor)

            shortcutTab
                .tabItem {
                    Label("快捷键", systemImage: "keyboard")
                }
                .tag(Tab.shortcuts)

            keyTab
                .tabItem {
                    Label("密钥", systemImage: "key")
                }
                .tag(Tab.key)

            aboutTab
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
                .tag(Tab.about)
        }
        .padding(.horizontal, DS.s4)
        .padding(.bottom, DS.s4)
        .frame(
            minWidth: 640,
            idealWidth: 640,
            maxWidth: 640,
            minHeight: 660,
            idealHeight: 660,
            maxHeight: 660
        )
        .background(DS.bg)
        .background(shortcutRecorder)
        .onAppear(perform: loadAIAPIKeys)
        .alert("设置失败", isPresented: settingsErrorBinding) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(settingsErrorMessage ?? "无法保存这个设置。")
        }
    }

    private var generalTab: some View {
        panelStack {
            macPanel("菜单栏") {
                toggleRow("启动时打开菜单栏应用", systemImage: "menubar.rectangle", isOn: launchAtLoginBinding)

                SWRowDivider()

                SWSettingsRow("最近笔记数量", systemImage: "list.number") {
                    Picker("最近笔记数量", selection: recentNotesLimitBinding) {
                        ForEach(SettingsStore.macRecentNotesLimitOptions, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .tint(DS.primary)
                }
            }

            macPanel("笔记") {
                toggleRow("笔记默认置顶", systemImage: "pin.fill", isOn: $settings.pinNewNotesByDefault)
                SWRowDivider()
                toggleRow("新建笔记自动加密", subtitle: vaultStore.isKeyLoaded ? nil : "需要先在“密钥”中创建或加载密钥。", systemImage: "lock", isOn: newEncryptedNoteBinding)
                    .disabled(!vaultStore.isKeyLoaded)
            }

            macPanel("存储") {
                SWSettingsRow(
                    vaultStore.isUsingICloudStorage ? "iCloud 文件夹" : "本地文件夹",
                    subtitle: vaultStore.isUsingICloudStorage ? "笔记文件直接位于 iCloud Drive 公开文件夹中。" : "当前未使用 iCloud，已回退到本地存储。",
                    systemImage: vaultStore.isUsingICloudStorage ? "icloud" : "folder",
                    tint: vaultStore.isUsingICloudStorage ? DS.primaryDeep : DS.pro
                ) {
                    Button("打开") {
                        openStorageFolder()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }

            macPanel("主题") {
                SWSettingsRow("主题色", systemImage: "paintpalette", tint: DS.primaryDeep) {
                    Picker("主题色", selection: $settings.macTheme) {
                        ForEach(MacTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .tint(DS.primary)
                }
            }
        }
    }

    private var aboutTab: some View {
        panelStack {
            SWSectionPanel {
                VStack(spacing: DS.s8){
                    VStack(spacing: DS.s6) {
                        aboutLogo
                        
                        VStack(spacing: DS.s2) {
                            Text("Seal Note")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(DS.textEmphasize)
                            
                            Text("v0.2")
                                .font(DS.caption())
                                .foregroundStyle(DS.textSubtle)
                            
                            Text("快速记录，不打断当前工作。")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(DS.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    HStack(alignment: .top, spacing: DS.s6) {
                        feature(
                            systemImage: "menubar.rectangle",
                            title: "快速捕捉",
                            detail: "从菜单栏新建或打开最近笔记，不打断当前工作。"
                        )
                        
                        feature(
                            systemImage: "doc.plaintext",
                            title: "自由迁移",
                            detail: "以标准 Markdown 文件保存，方便同步、迁移和跨工具读取。"
                        )
                        
                        feature(
                            systemImage: "lock.shield",
                            title: "安心加密",
                            detail: "端侧加密，密钥文件由你保存和管理。"
                        )
                    }
                    .padding(.horizontal, DS.s6)
                }
                .padding(.vertical, DS.s8)
            }

            macPanel("组件") {
                SWSettingsRow("查看组件", systemImage: "square.grid.2x2") {
                    Button {
                        MacMenuBarController.shared.openComponentCatalogWindow()
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.body)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("打开组件目录")
                }
            }

            macPanel("维护日志") {
                SWSettingsRow("开启日志记录", subtitle: "记录保存、索引等元数据；不记录正文或密钥。", systemImage: "doc.text.magnifyingglass") {
                    if settings.maintenanceLoggingEnabled {
                        HStack(spacing: DS.s2) {
                            Button {
                                openMaintenanceLogFolder()
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .help("打开日志文件夹")

                            Button("关闭", role: .destructive) {
                                settings.maintenanceLoggingEnabled = false
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }
                    } else {
                        Button("开启") {
                            settings.maintenanceLoggingEnabled = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .tint(DS.primary)
                    }
                }
            }
        
        }
    }
    
    private func feature(systemImage: String, title: String, detail: String) -> some View {
        VStack(spacing: DS.s2) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.primaryDeep)
                .frame(width: 32, height: 32)
                .background(DS.primaryContainer)
                .clipShape(Circle())

            Text(title)
                .font(DS.bodyLg().weight(.semibold))
                .foregroundStyle(DS.textStrong)
                .multilineTextAlignment(.center)

            Text(detail)
                .font(DS.caption())
                .foregroundStyle(DS.textSubtle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var editorTab: some View {
        panelStack {
            macPanel("编辑体验") {
                SWSettingsRow("编辑字号", systemImage: "textformat.size") {
                    VStack(alignment: .trailing, spacing: DS.s1) {
                        Text(String(format: "%.0f", settings.macEditorFontSize))
                            .font(DS.caption())
                            .foregroundColor(DS.textSecondary)
                            .monospacedDigit()
                        Slider(
                            value: fontSizeBinding,
                            in: SettingsStore.macEditorFontSizeRange,
                            step: SettingsStore.macEditorFontSizeStep
                        )
                        .frame(width: 150)
                        .tint(DS.primary)
                    }
                }

                SWRowDivider()

                SWSettingsRow("行高", systemImage: "line.3.horizontal.decrease") {
                    VStack(alignment: .trailing, spacing: DS.s1) {
                        Text(String(format: "%.2fx", settings.macEditorLineHeightMultiple))
                            .font(DS.caption())
                            .foregroundColor(DS.textSecondary)
                            .monospacedDigit()
                        Slider(
                            value: lineHeightBinding,
                            in: SettingsStore.macEditorLineHeightRange,
                            step: 0.05
                        )
                        .frame(width: 150)
                        .tint(DS.primary)
                    }
                }
            }

            macPanel("编辑行为") {
                toggleRow("复制为更宽松的 Markdown 段落", subtitle: "复制时自动补充段落空行，便于粘贴到 Typora 等 Markdown 编辑器使用。", systemImage: "doc.on.clipboard", isOn: $settings.copyAddsParagraphSpacing)

                SWRowDivider()

                toggleRow("关闭空白笔记时自动丢弃", systemImage: "trash", isOn: $settings.autoDeleteEmptyNotes)

                SWRowDivider()

                toggleRow("自动命名笔记", subtitle: "开启后每次自动保存都会按正文重新命名；关闭时仅保留手动标题和首次标题规则。", systemImage: "text.cursor", isOn: $settings.autoRenameNotesOnSave)

                SWRowDivider()

                toggleRow("不将 Hex 色值识别为标签", subtitle: "忽略 #RRGGBB 和含透明度的 #RRGGBBAA 色值。", systemImage: "paintpalette", isOn: $settings.excludeHexColorsFromTags)
            }
        }
    }

    private var aiTitleTab: some View {
        panelStack {
            SWPageHeader(
                title: "AI",
                subtitle: "关闭便利贴后为菜单栏和 iCloud 文件名生成标题",
                systemImage: "sparkles",
                tint: DS.primaryDeep
            )

            macPanel("开关") {
                toggleRow("开启 AI 标题", subtitle: "关闭编辑器后发送正文给所选服务生成标题；不会改写正文。", systemImage: "sparkles", isOn: $settings.macAITitleEnabled)

                SWRowDivider()

                toggleRow("标题例外", subtitle: "如果第一行已经是 # 标题，则跳过 AI 标题。", systemImage: "number", isOn: $settings.macAITitleSkipsMarkdownHeading)
            }

            macPanel("服务") {
                SWSettingsRow("标题服务", systemImage: "server.rack", tint: DS.primaryDeep) {
                    Picker("标题服务", selection: $settings.macAITitleProvider) {
                        ForEach(MacAITitleProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .tint(DS.primary)
                }

                SWRowDivider()

                apiKeyRow(
                    title: "DeepSeek API Key",
                    provider: .deepSeek,
                    key: $deepSeekAPIKey
                )

                SWRowDivider()

                apiKeyRow(
                    title: "Gemini API Key",
                    provider: .gemini,
                    key: $geminiAPIKey
                )

                if let apiKeyStatusMessage {
                    helperText(apiKeyStatusMessage)
                }
            }

            macPanel("Prompt") {
                VStack(alignment: .leading, spacing: DS.s2) {
                    HStack {
                        Label("自定义 Prompt", systemImage: "text.quote")
                            .font(DS.body())
                            .foregroundColor(DS.textStrong)
                        Spacer()
                        Button("恢复默认") {
                            settings.resetMacAITitlePrompt()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }

                    TextEditor(text: $settings.macAITitlePrompt)
                        .font(.system(size: 13, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(DS.s2)
                        .frame(height: 96)
                        .background(DS.surfaceSunken)
                        .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                                .stroke(DS.line, lineWidth: 0.5)
                        )

                    helperText("正文会发送给当前选择的服务商；加密笔记在已解锁编辑时也会参与生成。")
                }
            }
        }
    }

    private var shortcutTab: some View {
        panelStack {
            macPanel("常用操作") {
                LazyVGrid(columns: shortcutGridColumns, alignment: .leading, spacing: DS.s2) {
                    shortcutTile(
                        title: "新建笔记",
                        value: ShortcutStore.displayStringForKey(
                            keyCode: shortcutStore.newNoteKey.keyCode,
                            modifiers: shortcutStore.newNoteKey.modifiers
                        ),
                        isRecording: recordingAction == .newNote,
                        onRecord: { recordingAction = .newNote }
                    )

                    ForEach(EditorShortcutAction.allCases) { action in
                        let shortcut = shortcutStore.shortcut(for: action)
                        shortcutTile(
                            title: action.title,
                            value: ShortcutStore.displayStringForKey(
                                keyCode: shortcut.keyCode,
                                modifiers: shortcut.modifiers
                            ),
                            isRecording: recordingAction == .editor(action),
                            onRecord: { recordingAction = .editor(action) }
                        )
                    }
                }
            }

            macPanel("Markdown 格式") {
                LazyVGrid(columns: shortcutGridColumns, alignment: .leading, spacing: DS.s2) {
                    ForEach(MarkdownShortcutAction.allCases) { action in
                        let shortcut = shortcutStore.shortcut(for: action)
                        shortcutTile(
                            title: action.title,
                            value: ShortcutStore.displayStringForKey(
                                keyCode: shortcut.keyCode,
                                modifiers: shortcut.modifiers
                            ),
                            isRecording: recordingAction == .markdown(action),
                            onRecord: { recordingAction = .markdown(action) }
                        )
                    }
                }

            }

            HStack(spacing: DS.s2) {
                helperText(recordingAction == nil ? "点击录制后按下新的组合键；Esc 取消。" : "正在录制：按下新的组合键，或按 Esc 取消。")
                Spacer(minLength: DS.s3)
                Button("恢复默认") {
                    shortcutStore.resetAllShortcuts()
                    recordingAction = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    private var keyTab: some View {
        panelStack {
            let keyStatus = vaultStore.macKeyStatus
            macPanel("密钥状态") {
                SWSettingsRow(
                    keyStatusTitle(keyStatus),
                    subtitle: keyManagementSubtitle(for: keyStatus),
                    systemImage: keyManagementIcon(for: keyStatus),
                    tint: keyManagementTint(for: keyStatus)
                ) {
                    keyManagementActions(for: keyStatus)
                }
            }
        }
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { settings.macEditorFontSize },
            set: { newValue in
                settings.macEditorFontSize = newValue
            }
        )
    }

    private func keyStatusTitle(_ status: MacVaultKeyStatus) -> String {
        switch status {
        case .noReference:
            return "未加载密钥"
        case .available:
            return "密钥已加载"
        case .invalid(.keyReplaced):
            return "密钥已被替换"
        case .invalid(.keyDownloadPending):
            return "密钥正在下载"
        case .invalid:
            return "密钥失效"
        }
    }

    private func keyStatusSubtitle(_ status: MacVaultKeyStatus) -> String {
        switch status {
        case .noReference:
            return "加载密钥后才能查看加密笔记正文"
        case .available:
            return "这台 Mac 已经可以解锁加密笔记"
        case .invalid(.keyDownloadPending):
            return "密钥文件仍在从 iCloud 下载，请稍后再试"
        case .invalid:
            return "密钥需要重新定位后才能解锁加密笔记"
        }
    }

    private func keyManagementSubtitle(for status: MacVaultKeyStatus) -> String {
        let encryptedCount = vaultStore.encryptedEntryCount
        switch status {
        case .noReference where encryptedCount > 0:
            return "发现 \(encryptedCount) 条加密笔记，请优先加载原密钥。"
        case .noReference:
            return "当前未加载密钥。密钥只会在本机读取，不会保存到钥匙串。"
        case .available:
            return abbreviatedDisplayPath(vaultStore.keyFileDisplayPath)
                ?? "请妥善保存密钥，丢失后无法恢复加密笔记。"
        case .invalid(.keyDownloadPending):
            return "已请求 iCloud 下载密钥文件。下载完成后再打开加密笔记。"
        case .invalid where encryptedCount > 0:
            return "密钥失效，\(encryptedCount) 条加密笔记需要原密钥解锁。"
        case .invalid:
            return "密钥不可用、格式无效，或内容已被替换。"
        }
    }

    private func abbreviatedDisplayPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let cloudDocsPath = "/Library/Mobile Documents/com~apple~CloudDocs"
        guard let cloudDocsRange = standardizedPath.range(of: cloudDocsPath) else {
            return standardizedPath
        }

        let relativePath = standardizedPath[cloudDocsRange.upperBound...]
        guard relativePath.isEmpty || relativePath.hasPrefix("/") else {
            return standardizedPath
        }
        return "iCloud Drive" + relativePath
    }

    private func keyManagementIcon(for status: MacVaultKeyStatus) -> String {
        switch status {
        case .noReference:
            return "lock.shield"
        case .available:
            return "checkmark.shield.fill"
        case .invalid:
            return "exclamationmark.triangle"
        }
    }

    private func keyManagementTint(for status: MacVaultKeyStatus) -> Color {
        switch status {
        case .noReference:
            return DS.textSubtle
        case .available:
            return DS.primaryDeep
        case .invalid:
            return DS.destructive
        }
    }

    @ViewBuilder
    private func keyManagementActions(for status: MacVaultKeyStatus) -> some View {
        switch status {
        case .noReference:
            if vaultStore.encryptedEntryCount > 0 {
                HStack(spacing: DS.s2) {
                    Button("加载已有密钥") {
                        loadKey()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(DS.primary)

                    Button("创建新密钥") {
                        createNewKey()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            } else {
                HStack(spacing: DS.s2) {
                    Button("创建新密钥") {
                        createNewKey()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(DS.primary)

                    Button("加载已有密钥") {
                        loadKey()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        case .available:
            HStack(spacing: DS.s2) {
                Button {
                    openKeyLocation()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("打开密钥位置")

                Button("移除引用", role: .destructive) {
                    unloadKey()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        case .invalid:
            HStack(spacing: DS.s2) {
                Button("重新定位密钥") {
                    loadKey()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(DS.primary)

                Button("移除引用", role: .destructive) {
                    unloadKey()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    private var lineHeightBinding: Binding<Double> {
        Binding(
            get: { settings.macEditorLineHeightMultiple },
            set: { settings.macEditorLineHeightMultiple = $0 }
        )
    }

    private var newEncryptedNoteBinding: Binding<Bool> {
        Binding(
            get: { settings.preferredNoteMode == .encrypted },
            set: { isOn in
                settings.preferredNoteMode = isOn && vaultStore.isKeyLoaded ? .encrypted : .plain
            }
        )
    }

    private var recentNotesLimitBinding: Binding<Int> {
        Binding(
            get: { settings.macRecentNotesLimit },
            set: { settings.macRecentNotesLimit = $0 }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { isEnabled in
                do {
                    try settings.setLaunchAtLogin(isEnabled)
                } catch {
                    settingsErrorMessage = "无法更新登录项设置：\(error.localizedDescription)"
                }
            }
        )
    }

    private var settingsErrorBinding: Binding<Bool> {
        Binding(
            get: { settingsErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    settingsErrorMessage = nil
                }
            }
        )
    }

    private var shortcutRecorder: some View {
        ShortcutRecorderView(recordingAction: $recordingAction) { action, shortcut in
            switch action {
            case .newNote:
                shortcutStore.setNewNoteShortcut(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
            case .markdown(let markdownAction):
                shortcutStore.setMarkdownShortcut(shortcut, for: markdownAction)
            case .editor(let editorAction):
                shortcutStore.setEditorShortcut(shortcut, for: editorAction)
            }
            recordingAction = nil
        }
        .frame(width: 0, height: 0)
    }

    private var shortcutGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: DS.s2),
            GridItem(.flexible(), spacing: DS.s2)
        ]
    }

    private func apiKeyRow(title: String, provider: MacAITitleProvider, key: Binding<String>) -> some View {
        SWSettingsRow(title, subtitle: provider == settings.macAITitleProvider ? "当前服务" : nil, systemImage: "key.viewfinder", tint: provider == settings.macAITitleProvider ? DS.primaryDeep : DS.textSubtle) {
            HStack(spacing: DS.s2) {
                SecureField(title, text: key)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 210)
                Button("保存") {
                    saveAIAPIKey(key.wrappedValue, provider: provider)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                SWStatusBadge(key.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未保存" : "已填写", style: key.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .neutral : .success)
            }
        }
    }

    private func panelStack<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        MacSettingsPage(content: content)
    }

    private func macPanel<Content: View>(
        _ title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        SWSectionPanel {
            VStack(alignment: .leading, spacing: DS.s2) {
                content()
            }
            .padding(.horizontal, DS.s3)
            .padding(.vertical, DS.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func toggleRow(_ title: String, subtitle: String? = nil, systemImage: String? = nil, isOn: Binding<Bool>) -> some View {
        SWSettingsRow(
            title,
            subtitle: subtitle,
            systemImage: systemImage ?? (isOn.wrappedValue ? "checkmark.circle.fill" : "circle"),
            trailingMinWidth: 72
        ) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(DS.primary)
        }
    }

    private func shortcutTile(title: String, value: String, isRecording: Bool, onRecord: @escaping () -> Void) -> some View {
        HStack(spacing: DS.s2) {
            Image(systemName: isRecording ? "record.circle" : "keyboard")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isRecording ? DS.primary : DS.textSubtle)
                .frame(width: 24, height: 24)
                .background((isRecording ? DS.primary : DS.textSubtle).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))

            Text(title)
                .font(DS.body())
                .foregroundColor(DS.textStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            Spacer(minLength: DS.s1)

            Text(value)
                .font(DS.caption())
                .foregroundColor(isRecording ? DS.primary : DS.textSecondary)
                .monospacedDigit()
                .lineLimit(1)

            Button {
                onRecord()
            } label: {
                Label(isRecording ? "正在录制" : "录制快捷键", systemImage: isRecording ? "record.circle.fill" : "record.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .controlSize(.regular)
            .tint(isRecording ? DS.primary : nil)
            .help(isRecording ? "正在录制" : "录制快捷键")
        }
        .padding(.horizontal, DS.s2)
        .padding(.vertical, DS.s2)
        .frame(minHeight: 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            if isRecording {
                RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                    .stroke(DS.primary.opacity(0.26), lineWidth: 0.5)
            }
        }
    }

    private func statusRow(_ title: String, systemImage: String, tint: Color) -> some View {
        SWSettingsRow(title, systemImage: systemImage, tint: tint) {
            EmptyView()
        }
    }

    private func helperText(_ text: String) -> some View {
        Text(text)
            .font(DS.caption())
            .foregroundColor(DS.textSubtle)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.s1)
    }

    @ViewBuilder
    private var aboutLogo: some View {
        if let image = MacAppIconController.image(for: settings.macTheme) {
            Image(nsImage: image)
                .resizable()
                .frame(width: 82, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: DS.floatShadow.color, radius: DS.floatShadow.radius, x: DS.floatShadow.x, y: DS.floatShadow.y)
                .id(settings.macTheme)
        } else {
            Color.clear
                .frame(width: 82, height: 82)
        }
    }

    private func loadAIAPIKeys() {
        deepSeekAPIKey = settings.loadMacAITitleAPIKey(for: .deepSeek)
        geminiAPIKey = settings.loadMacAITitleAPIKey(for: .gemini)
    }

    private func saveAIAPIKey(_ key: String, provider: MacAITitleProvider) {
        do {
            try settings.saveMacAITitleAPIKey(key, for: provider)
            apiKeyStatusMessage = key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "\(provider.title) API Key 已移除。"
                : "\(provider.title) API Key 已保存到本机钥匙串。"
        } catch {
            settingsErrorMessage = "无法保存 \(provider.title) API Key：\(error.localizedDescription)"
        }
    }

    private func openStorageFolder() {
        guard let containerURL = vaultStore.storageContainerURL else {
            let alert = NSAlert()
            alert.messageText = "无法打开文件夹"
            alert.informativeText = "当前没有可用的存储目录。"
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }

        if !NSWorkspace.shared.open(containerURL) {
            let alert = NSAlert()
            alert.messageText = "无法打开文件夹"
            alert.informativeText = "Finder 未能打开：\(containerURL.path)"
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }

    private func openKeyLocation() {
        guard let displayPath = vaultStore.keyFileDisplayPath else {
            settingsErrorMessage = "当前没有可打开的密钥位置。"
            return
        }

        let url = URL(fileURLWithPath: displayPath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let parentURL = url.deletingLastPathComponent()
            if !NSWorkspace.shared.open(parentURL) {
                settingsErrorMessage = "Finder 未能打开：\(parentURL.path)"
            }
        }
    }

    private func openMaintenanceLogFolder() {
        let url = MaintenanceLogStore.shared.logsDirectory
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            if !NSWorkspace.shared.open(url) {
                settingsErrorMessage = "Finder 未能打开：\(url.path)"
            }
        } catch {
            settingsErrorMessage = "无法打开日志文件夹：\(error.localizedDescription)"
        }
    }

    private func loadKey() {
        let panel = NSOpenPanel()
        panel.title = "加载已有密钥"
        panel.message = "密钥只会在本机读取，不会上传。"
        panel.allowedContentTypes = [.init(filenameExtension: "snkey")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            do {
                _ = try await vaultStore.importKeyFile(from: url)
            } catch {
                await MainActor.run {
                    handleKeyImportFailure(error, selectedURL: url)
                }
            }
        }
    }

    private func unloadKey() {
        if vaultStore.encryptedEntryCount == 0 {
            confirmRemoveKeyReference()
        } else if vaultStore.isKeyLoaded {
            confirmUsableKeyRemoval()
        } else {
            confirmInvalidKeyRemoval()
        }
    }

    private func confirmRemoveKeyReference() {
        let alert = NSAlert()
        alert.messageText = "移除密钥引用？"
        alert.informativeText = "只会让 Seal Note 忘记密钥位置，不会删除密钥本身。"
        alert.addButton(withTitle: "移除密钥引用")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                try await vaultStore.unloadKey()
            } catch {
                await MainActor.run {
                    settingsErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func confirmUsableKeyRemoval() {
        let alert = NSAlert()
        alert.messageText = "移除密钥引用前如何处理加密笔记？"
        alert.informativeText = affectedEncryptedNotesMessage(prefix: "移除密钥引用前，需要先删除这些加密笔记，或全部解密为明文。")
        alert.addButton(withTitle: "删除全部加密笔记")
        alert.addButton(withTitle: "先全部解密成明文")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { await runKeyRemovalAction { try await self.vaultStore.permanentlyDeleteAllEncryptedNotes() } }
        case .alertSecondButtonReturn:
            decryptAllEncryptedNotesAndRemoveKey()
        default:
            break
        }
    }

    private func confirmInvalidKeyRemoval() {
        let alert = NSAlert()
        alert.messageText = "密钥失效时移除密钥引用？"
        alert.informativeText = affectedEncryptedNotesMessage(prefix: "当前密钥不可用，无法在此时解密加密笔记。若仍保留原密钥，请取消并先重新定位密钥。")
        alert.addButton(withTitle: "删除全部加密笔记")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await runKeyRemovalAction { try await self.vaultStore.permanentlyDeleteAllEncryptedNotes() } }
    }

    private func decryptAllEncryptedNotesAndRemoveKey() {
        Task { await runKeyRemovalAction { try await self.vaultStore.decryptAllEncryptedNotesAndRemoveKey() } }
    }

    private func runKeyRemovalAction(_ action: @escaping () async throws -> Int) async {
        do {
            _ = try await action()
            StickyNoteWindowManager.shared.closeAllWindows()
        } catch {
            await MainActor.run {
                settingsErrorMessage = error.localizedDescription
            }
        }
    }

    private func affectedEncryptedNotesMessage(prefix: String) -> String {
        "\(prefix)\n\n受影响范围包括当前列表和回收站中的 \(vaultStore.encryptedEntryCount) 条加密笔记。"
    }

    private func createNewKey() {
        guard !vaultStore.hasKeyReference else {
            unloadKey()
            return
        }

        guard vaultStore.encryptedEntryCount == 0 else {
            confirmDeleteEncryptedNotesAndCreateKey()
            return
        }

        presentCreateKeyPanel()
    }

    private func confirmDeleteEncryptedNotesAndCreateKey() {
        let alert = NSAlert()
        alert.messageText = "创建新密钥会影响已有加密笔记"
        alert.informativeText = affectedEncryptedNotesMessage(prefix: "新密钥无法解锁现有加密笔记。继续前必须删除这些加密笔记。")
        alert.addButton(withTitle: "删除这些加密笔记并创建新密钥")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            do {
                _ = try await vaultStore.permanentlyDeleteAllEncryptedNotes()
                await MainActor.run {
                    presentCreateKeyPanel()
                }
            } catch {
                await MainActor.run {
                    settingsErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func presentCreateKeyPanel() {
        let alert = NSAlert()
        alert.messageText = "创建新密钥？"
        alert.informativeText = "请将密钥保存到安全位置。丢失密钥将无法解密加密笔记。"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let savePanel = NSSavePanel()
        savePanel.title = "保存密钥"
        savePanel.message = "保存成功后，Seal Note 会记住这个密钥的位置。"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        savePanel.nameFieldStringValue = "Seal Note-密钥-\(formatter.string(from: Date())).snkey"
        savePanel.allowedContentTypes = [.init(filenameExtension: "snkey")!]
        guard savePanel.runModal() == .OK, let saveURL = savePanel.url else { return }

        Task {
            do {
                try await vaultStore.createKeyFile(at: saveURL)
            } catch {
                await MainActor.run {
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "创建失败"
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.addButton(withTitle: "确定")
                    errorAlert.runModal()
                }
            }
        }
    }

    private func handleKeyImportFailure(_ error: Error, selectedURL: URL) {
        guard let keyError = error as? VaultKeyFileError, keyError == .keyMismatch else {
            settingsErrorMessage = error.localizedDescription
            return
        }

        let alert = NSAlert()
        alert.messageText = "所选密钥无法解锁现有加密笔记"
        alert.informativeText = affectedEncryptedNotesMessage(prefix: "默认不会保存这次选择的密钥。")
        alert.addButton(withTitle: "重新选择密钥")
        alert.addButton(withTitle: "删除这些加密笔记并使用此密钥")
        alert.addButton(withTitle: "取消")
        if alert.buttons.indices.contains(1) {
            alert.buttons[1].hasDestructiveAction = true
        }

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            loadKey()
        case .alertSecondButtonReturn:
            Task {
                do {
                    _ = try await vaultStore.permanentlyDeleteAllEncryptedNotes()
                    _ = try await vaultStore.importKeyFile(from: selectedURL)
                    StickyNoteWindowManager.shared.closeAllWindows()
                } catch {
                    await MainActor.run {
                        settingsErrorMessage = error.localizedDescription
                    }
                }
            }
        default:
            break
        }
    }
}

#Preview("设置 - 通用") {
    MacSettingsView(selectedTab: .general)
}

#Preview("设置 - 编辑器") {
    MacSettingsView(selectedTab: .editor)
}

#Preview("设置 - 快捷键") {
    MacSettingsView(selectedTab: .shortcuts)
}

#Preview("设置 - 密钥") {
    MacSettingsView(selectedTab: .key)
}

#Preview("设置 - 关于") {
    MacSettingsView(selectedTab: .about)
}

private enum MacShortcutRecordingAction: Equatable, Identifiable {
    case newNote
    case markdown(MarkdownShortcutAction)
    case editor(EditorShortcutAction)

    var id: String {
        switch self {
        case .newNote: return "newNote"
        case .markdown(let action): return "markdown.\(action.rawValue)"
        case .editor(let action): return "editor.\(action.rawValue)"
        }
    }
}

private struct MacSettingsPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s3) {
            content()
            Spacer(minLength: 0)
        }
        .padding(.top, DS.s6)
        .padding(.horizontal, DS.s3)
        .padding(.bottom, DS.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.bg)
    }
}

private struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var recordingAction: MacShortcutRecordingAction?
    let onRecord: (MacShortcutRecordingAction, MarkdownShortcut) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onRecord = onRecord
        view.onCancel = { recordingAction = nil }
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.recordingAction = recordingAction
        nsView.onRecord = onRecord
        nsView.onCancel = { recordingAction = nil }
        if recordingAction != nil {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class RecorderView: NSView {
        var recordingAction: MacShortcutRecordingAction?
        var onRecord: ((MacShortcutRecordingAction, MarkdownShortcut) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard let action = recordingAction else {
                super.keyDown(with: event)
                return
            }

            if event.keyCode == 53 {
                onCancel?()
                return
            }

            guard let keyEquivalent = event.charactersIgnoringModifiers?.lowercased(), !keyEquivalent.isEmpty else {
                return
            }

            let shortcut = MarkdownShortcut(
                keyCode: UInt32(event.keyCode),
                modifiers: ShortcutStore.carbonModifiers(from: event.modifierFlags),
                keyEquivalent: keyEquivalent
            )
            onRecord?(action, shortcut)
        }
    }
}
