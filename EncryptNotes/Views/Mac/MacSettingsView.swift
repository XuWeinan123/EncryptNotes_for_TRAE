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
    }

    @ObservedObject private var shortcutStore = ShortcutStore.shared
    @ObservedObject private var vaultStore = VaultStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var selectedTab: Tab
    @State private var recordingAction: MarkdownShortcutAction?
    @State private var settingsErrorMessage: String?
    @State private var deepSeekAPIKey = ""
    @State private var geminiAPIKey = ""
    @State private var apiKeyStatusMessage: String?

    init(selectedTab: Tab = .general) {
        _selectedTab = State(initialValue: selectedTab)
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

            aiTitleTab
                .tabItem {
                    Label("AI 标题", systemImage: "sparkles")
                }
                .tag(Tab.aiTitle)

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
                title: "AI 标题",
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

            macPanel("新建笔记") {
                shortcutRow(
                    title: "新建笔记",
                    value: ShortcutStore.displayStringForKey(
                        keyCode: shortcutStore.newNoteKey.keyCode,
                        modifiers: shortcutStore.newNoteKey.modifiers
                    ),
                    isRecording: false,
                    onRecord: {}
                )
                helperText("默认快捷键：⌃⌘Z")
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
                            isRecording: recordingAction == action,
                            onRecord: { recordingAction = action }
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
            SWPageHeader(
                title: "密钥",
                subtitle: vaultStore.isKeyLoaded ? "这台 Mac 已经可以解锁加密笔记" : "加载密钥后才能查看加密笔记正文",
                systemImage: vaultStore.isKeyLoaded ? "checkmark.shield.fill" : "lock.shield",
                tint: DS.primaryDeep
            )

            if vaultStore.isKeyLoaded {
                macPanel("密钥状态") {
                    SWSettingsRow("密钥已加载到本机", subtitle: "请妥善保存密钥文件，丢失后无法恢复加密笔记。", systemImage: "checkmark.shield.fill", tint: DS.primaryDeep) {
                        SWStatusBadge("可解锁", style: .success)
                    }
                    SWRowDivider()

                    SWSettingsRow("导出密钥文件", subtitle: "保存为 .bkwkey 文件", systemImage: "square.and.arrow.up") {
                        Button("导出…") {
                            exportKey()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    SWRowDivider()

                    SWSettingsRow("移除本机密钥", subtitle: "不删除笔记，只让加密内容回到锁定状态", systemImage: "lock.slash", tint: DS.destructive) {
                        Button("移除", role: .destructive) {
                            unloadKey()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } else {
                macPanel("密钥状态") {
                    SWSettingsRow("本机未加载密钥", subtitle: "密钥文件只会在本机读取，不会上传。", systemImage: "lock.shield", tint: DS.textSubtle) {
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
            shortcutStore.setMarkdownShortcut(shortcut, for: action)
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

    private func loadKey() {
        MacMenuBarController.shared.loadKeyFile()
    }

    private func unloadKey() {
        let alert = NSAlert()
        alert.messageText = "移除本机密钥？"
        alert.informativeText = "移除后，所有加密笔记将无法查看，直到重新加载密钥。"
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                try? await vaultStore.unloadKey()
                StickyNoteWindowManager.shared.closeAllWindows()
            }
        }
    }

    private func exportKey() {
        do {
            let keyURL = try vaultStore.exportKeyFile()
            let panel = NSSavePanel()
            panel.title = "导出密钥文件"
            panel.message = "请将密钥文件保存到安全的位置。"
            panel.nameFieldStringValue = keyURL.lastPathComponent
            panel.allowedContentTypes = [.init(filenameExtension: "bkwkey")!]
            if panel.runModal() == .OK, let saveURL = panel.url {
                try? FileManager.default.copyItem(at: keyURL, to: saveURL)
            }
            try? FileManager.default.removeItem(at: keyURL)
        } catch {
            let alert = NSAlert()
            alert.messageText = "导出失败"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }

    private func createNewKey() {
        let alert = NSAlert()
        alert.messageText = "创建新的加密空间？"
        alert.informativeText = "将生成新的密钥，你需要妥善保存密钥文件。如果 iCloud 中已有加密笔记，将无法使用新密钥解锁。"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                do {
                    try await vaultStore.createKey()
                    let keyURL = try vaultStore.exportKeyFile()
                    let savePanel = NSSavePanel()
                    savePanel.title = "保存密钥文件"
                    savePanel.message = "请立即将密钥文件保存到安全的位置。丢失密钥将无法解密加密笔记。"
                    savePanel.nameFieldStringValue = keyURL.lastPathComponent
                    savePanel.allowedContentTypes = [.init(filenameExtension: "bkwkey")!]
                    if savePanel.runModal() == .OK, let saveURL = savePanel.url {
                        try? FileManager.default.copyItem(at: keyURL, to: saveURL)
                    }
                    try? FileManager.default.removeItem(at: keyURL)
                } catch {
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

#Preview("设置 - 通用") {
    MacSettingsView(selectedTab: .general)
}

#Preview("设置 - 编辑器") {
    MacSettingsView(selectedTab: .editor)
}

#Preview("设置 - AI 标题") {
    MacSettingsView(selectedTab: .aiTitle)
}

#Preview("设置 - 快捷键") {
    MacSettingsView(selectedTab: .shortcuts)
}

#Preview("设置 - 密钥") {
    MacSettingsView(selectedTab: .key)
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
    @Binding var recordingAction: MarkdownShortcutAction?
    let onRecord: (MarkdownShortcutAction, MarkdownShortcut) -> Void

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
        var recordingAction: MarkdownShortcutAction?
        var onRecord: ((MarkdownShortcutAction, MarkdownShortcut) -> Void)?
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
