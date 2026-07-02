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
    @State private var logStatusMessage: String?

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
            SWPageHeader(
                title: "通用设置",
                subtitle: "调整菜单栏、置顶、存储位置和主题",
                systemImage: "gearshape",
                tint: DS.primaryDeep
            )

            macPanel("菜单栏") {
                toggleRow("启动时打开菜单栏应用", subtitle: "登录 Mac 后自动启动应用，并显示在菜单栏中。", systemImage: "menubar.rectangle", isOn: launchAtLoginBinding)

                SWRowDivider()

                SWSettingsRow("最近笔记数量", subtitle: "控制菜单栏中显示的最近笔记数量", systemImage: "list.number") {
                    Picker("最近笔记数量", selection: recentNotesLimitBinding) {
                        ForEach(Array(SettingsStore.macRecentNotesLimitRange), id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 86)
                }
            }

            macPanel("笔记") {
                toggleRow("笔记默认置顶", subtitle: "新建笔记窗口默认保持在其他窗口上方。", systemImage: "pin.fill", isOn: $settings.pinNewNotesByDefault)
                SWRowDivider()
                toggleRow("新建笔记自动加密", subtitle: vaultStore.isKeyLoaded ? "从菜单栏新建的笔记会直接保存为加密笔记。" : "需要先在“密钥”中创建或加载 .bkwkey 文件。", systemImage: "lock", isOn: newEncryptedNoteBinding)
                    .disabled(!vaultStore.isKeyLoaded)
            }

            macPanel("存储") {
                SWSettingsRow(
                    vaultStore.isUsingICloudStorage ? "iCloud 文件夹" : "本地文件夹",
                    subtitle: vaultStore.isUsingICloudStorage ? "笔记文件直接位于 iCloud Drive 公开文件夹中。" : "当前未使用 iCloud，已回退到本地存储。",
                    systemImage: vaultStore.isUsingICloudStorage ? "icloud" : "folder",
                    tint: vaultStore.isUsingICloudStorage ? DS.primaryDeep : DS.pro
                ) {
                    Button("打开…") {
                        openStorageFolder()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            macPanel("主题") {
                SWSettingsRow("主题色", subtitle: "影响按钮、选中态和强调色", systemImage: "paintpalette", tint: DS.primaryDeep) {
                    Picker("主题色", selection: $settings.macTheme) {
                        ForEach(MacTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                    .tint(DS.primary)
                }
            }
        }
    }

    private var aboutTab: some View {
        panelStack {
            SWSectionPanel {
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
                .padding(.vertical, DS.s4)
            }

            macPanel("欢迎") {
                SWSettingsRow("菜单栏便签", subtitle: "从右上角菜单快速新建、打开最近笔记。", systemImage: "menubar.rectangle") {
                    EmptyView()
                }
                SWRowDivider()
                SWSettingsRow("Markdown 文件", subtitle: "每条笔记都是可同步、可迁移的 Markdown 文件。", systemImage: "doc.plaintext") {
                    EmptyView()
                }
                SWRowDivider()
                SWSettingsRow("正文加密", subtitle: "加密笔记只加密正文，密钥来自你选择的 .bkwkey 文件。", systemImage: "lock.shield") {
                    EmptyView()
                }
            }

            macPanel("维护日志") {
                toggleRow("记录维护日志", subtitle: "默认关闭；开启后记录保存、索引、冲突和文件操作元数据，不记录正文或密钥。", systemImage: "doc.text.magnifyingglass", isOn: $settings.maintenanceLoggingEnabled)

                SWRowDivider()

                SWSettingsRow("下载日志", subtitle: "导出本机维护日志，用于后续代码维护和问题排查。", systemImage: "square.and.arrow.down") {
                    HStack(spacing: DS.s2) {
                        Button("下载…") {
                            exportMaintenanceLog()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            openMaintenanceLogFolder()
                        } label: {
                            Label("打开文件夹", systemImage: "folder")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("打开日志文件夹")
                    }
                }

                if let logStatusMessage {
                    helperText(logStatusMessage)
                }
            }
        }
    }

    private var editorTab: some View {
        panelStack {
            SWPageHeader(
                title: "编辑器",
                subtitle: "调整便利贴正文输入和复制行为",
                systemImage: "textformat",
                tint: DS.primaryDeep
            )

            macPanel("编辑体验") {
                SWSettingsRow("编辑字号", subtitle: "仅影响 mac 便利贴编辑器。", systemImage: "textformat.size") {
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

                SWSettingsRow("行高", subtitle: "控制编辑器正文的阅读密度。", systemImage: "line.3.horizontal.decrease") {
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

                toggleRow("关闭空白笔记时自动丢弃", subtitle: "正文为空的便利贴关闭后直接移除。", systemImage: "trash", isOn: $settings.autoDeleteEmptyNotes)
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
                SWSettingsRow("标题服务", subtitle: "选择关闭编辑器后调用的模型服务", systemImage: "server.rack", tint: DS.primaryDeep) {
                    Picker("标题服务", selection: $settings.macAITitleProvider) {
                        ForEach(MacAITitleProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
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
                        .controlSize(.small)
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
            SWPageHeader(
                title: "快捷键",
                subtitle: "录制 mac 菜单栏应用的常用操作组合键",
                systemImage: "keyboard",
                tint: DS.primaryDeep
            )

            macPanel("常用操作") {
                shortcutRow(
                    title: "新建笔记",
                    value: ShortcutStore.displayStringForKey(
                        keyCode: shortcutStore.newNoteKey.keyCode,
                        modifiers: shortcutStore.newNoteKey.modifiers
                    ),
                    isRecording: false,
                    onRecord: {}
                )
                SWRowDivider()

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

                helperText("新建笔记默认快捷键：⌃⌘Z")
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

                helperText(recordingAction == nil ? "点击录制后按下新的组合键；Esc 取消。" : "正在录制：按下新的组合键，或按 Esc 取消。")
            }

            Button("恢复默认快捷键") {
                shortcutStore.resetAllShortcuts()
                recordingAction = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var keyTab: some View {
        panelStack {
            let keyFileAvailable = vaultStore.isConfiguredKeyFileAvailable
            SWPageHeader(
                title: "密钥",
                subtitle: vaultStore.isKeyLoaded
                    ? (keyFileAvailable ? "这台 Mac 已经可以解锁加密笔记" : "密钥文件需要重新定位后才能解锁加密笔记")
                    : "加载密钥后才能查看加密笔记正文",
                systemImage: vaultStore.isKeyLoaded && keyFileAvailable ? "checkmark.shield.fill" : "lock.shield",
                tint: DS.primaryDeep
            )

            if vaultStore.isKeyLoaded {
                macPanel("密钥状态") {
                    SWSettingsRow(
                        keyFileAvailable ? "密钥文件已配置" : "密钥文件不在原位置",
                        subtitle: vaultStore.keyFileDisplayPath ?? "请妥善保存密钥文件，丢失后无法恢复加密笔记。",
                        systemImage: keyFileAvailable ? "checkmark.shield.fill" : "exclamationmark.triangle",
                        tint: keyFileAvailable ? DS.primaryDeep : DS.destructive
                    ) {
                        if keyFileAvailable {
                            SWStatusBadge("可解锁", style: .success)
                        } else {
                            Button("重新定位") {
                                loadKey()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    SWRowDivider()

                    SWSettingsRow("移除密钥引用", subtitle: "移除前需要选择如何处理现有加密笔记", systemImage: "lock.slash", tint: DS.destructive) {
                        Button("移除", role: .destructive) {
                            unloadKey()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } else {
                macPanel("密钥状态") {
                    SWSettingsRow("未配置密钥文件", subtitle: "密钥文件只会在需要解密时读取，不会保存到钥匙串。", systemImage: "lock.shield", tint: DS.textSubtle) {
                        SWStatusBadge("锁定", style: .neutral)
                    }
                    SWRowDivider()

                    SWSettingsRow("加载密钥文件", subtitle: "选择已有 .bkwkey 文件", systemImage: "square.and.arrow.down") {
                        Button("加载…") {
                            loadKey()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    SWRowDivider()

                    SWSettingsRow("创建新的加密空间", subtitle: "生成新密钥并立即保存密钥文件", systemImage: "key.fill", tint: DS.primaryDeep) {
                        Button("创建…") {
                            createNewKey()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(DS.primary)
                    }
                }
            }

            macPanel("临时锁定") {
                toggleRow("睡眠或锁屏时临时上锁", subtitle: "打开的加密笔记会进入模糊锁定状态。", systemImage: "moon.zzz", isOn: $settings.lockEncryptedNotesOnSleep)
                SWRowDivider()
                toggleRow("非置顶窗口进入后台时临时上锁", subtitle: "未置顶的加密笔记失焦后需要重新解锁。", systemImage: "rectangle.on.rectangle.slash", isOn: $settings.lockUnpinnedEncryptedNotesOnBackground)
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
                .controlSize(.small)
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
        SWSettingsRow(title, subtitle: subtitle, systemImage: systemImage ?? (isOn.wrappedValue ? "checkmark.circle.fill" : "circle")) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(DS.primary)
        }
    }

    private func shortcutRow(title: String, value: String, isRecording: Bool, onRecord: @escaping () -> Void) -> some View {
        shortcutTile(title: title, value: value, isRecording: isRecording, onRecord: onRecord)
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
                Label(isRecording ? "录制中" : "录制", systemImage: isRecording ? "record.circle" : "record.circle")
                    .labelStyle(.iconOnly)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(width: 28, height: 28)
            .help(isRecording ? "正在录制" : "录制快捷键")
        }
        .padding(.horizontal, DS.s2)
        .padding(.vertical, DS.s2)
        .frame(minHeight: 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isRecording ? DS.primaryContainer : DS.surfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                .stroke(isRecording ? DS.primary.opacity(0.26) : DS.line, lineWidth: 0.5)
        )
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
        if let image = NSApp.applicationIconImage, image.isValid {
            Image(nsImage: image)
                .resizable()
                .frame(width: 82, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: DS.floatShadow.color, radius: DS.floatShadow.radius, x: DS.floatShadow.x, y: DS.floatShadow.y)
        } else {
            Image(systemName: "pencil")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(DS.primaryDeep)
                .frame(width: 82, height: 82)
                .background(DS.primaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: DS.floatShadow.color, radius: DS.floatShadow.radius, x: DS.floatShadow.x, y: DS.floatShadow.y)
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

    private func exportMaintenanceLog() {
        do {
            let logURL = try MaintenanceLogStore.shared.exportLogFile()
            let panel = NSSavePanel()
            panel.title = "下载维护日志"
            panel.message = "保存 Seal Note 的本机维护日志。"
            panel.nameFieldStringValue = "seal-note-maintenance.log"
            panel.allowedContentTypes = [.plainText]
            if panel.runModal() == .OK, let saveURL = panel.url {
                if FileManager.default.fileExists(atPath: saveURL.path) {
                    try FileManager.default.removeItem(at: saveURL)
                }
                try FileManager.default.copyItem(at: logURL, to: saveURL)
                logStatusMessage = "维护日志已导出。"
            }
        } catch {
            settingsErrorMessage = "无法导出维护日志：\(error.localizedDescription)"
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
        MacMenuBarController.shared.loadKeyFile()
    }

    private func unloadKey() {
        let alert = NSAlert()
        alert.messageText = "移除密钥前如何处理加密笔记？"
        alert.informativeText = "删除会永久移除加密笔记；解密和导出都需要当前密钥文件可用且匹配。"
        alert.addButton(withTitle: "永久删除加密笔记")
        alert.addButton(withTitle: "全部解密为明文")
        alert.addButton(withTitle: "解密导出并移除本地")
        alert.addButton(withTitle: "取消")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            confirmPermanentDeleteEncryptedNotes()
        case .alertSecondButtonReturn:
            decryptAllEncryptedNotesAndRemoveKey()
        case .alertThirdButtonReturn:
            exportPlaintextAndRemoveEncryptedNotes()
        default:
            break
        }
    }

    private func confirmPermanentDeleteEncryptedNotes() {
        let alert = NSAlert()
        alert.messageText = "永久删除所有加密笔记？"
        alert.informativeText = "这个操作不会移到回收站，删除后无法恢复。"
        alert.addButton(withTitle: "永久删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                _ = try await vaultStore.permanentlyDeleteAllEncryptedNotes()
                StickyNoteWindowManager.shared.closeAllWindows()
            } catch {
                await MainActor.run {
                    settingsErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func decryptAllEncryptedNotesAndRemoveKey() {
        Task {
            do {
                _ = try await vaultStore.decryptAllEncryptedNotesAndRemoveKey()
                StickyNoteWindowManager.shared.closeAllWindows()
            } catch {
                await MainActor.run {
                    settingsErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func exportPlaintextAndRemoveEncryptedNotes() {
        let panel = NSSavePanel()
        panel.title = "导出解密后的明文笔记"
        panel.message = "导出成功后，本地加密笔记会被永久移除。"
        panel.nameFieldStringValue = "Seal Note-解密笔记.zip"
        panel.allowedContentTypes = [.init(filenameExtension: "zip")!]
        guard panel.runModal() == .OK, let saveURL = panel.url else { return }

        Task {
            do {
                _ = try await vaultStore.exportPlaintextEncryptedNotesAndRemoveLocalNotes(to: saveURL)
                StickyNoteWindowManager.shared.closeAllWindows()
            } catch {
                await MainActor.run {
                    settingsErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func createNewKey() {
        guard !vaultStore.isKeyLoaded else {
            unloadKey()
            return
        }

        let alert = NSAlert()
        alert.messageText = "创建加密密钥？"
        alert.informativeText = "请将密钥文件保存到安全位置。丢失密钥将无法解密加密笔记。"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            let savePanel = NSSavePanel()
            savePanel.title = "保存密钥文件"
            savePanel.message = "保存成功后，Seal Note 会记住这个密钥文件的位置。"
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            savePanel.nameFieldStringValue = "Seal Note-密钥-\(formatter.string(from: Date())).bkwkey"
            savePanel.allowedContentTypes = [.init(filenameExtension: "bkwkey")!]
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

private enum MacShortcutRecordingAction: Equatable, Identifiable {
    case markdown(MarkdownShortcutAction)
    case editor(EditorShortcutAction)

    var id: String {
        switch self {
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
