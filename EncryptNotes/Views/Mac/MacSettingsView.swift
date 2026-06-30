import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MacSettingsView: View {
    @ObservedObject private var shortcutStore = ShortcutStore.shared
    @ObservedObject private var vaultStore = VaultStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var recordingAction: MarkdownShortcutAction?

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("通用", systemImage: "gear")
                }

            shortcutTab
                .tabItem {
                    Label("快捷键", systemImage: "keyboard")
                }

            keyTab
                .tabItem {
                    Label("密钥", systemImage: "key")
                }
        }
        .padding(.horizontal, DS.s4)
        .padding(.bottom, DS.s4)
        .frame(
            minWidth: 640,
            idealWidth: 640,
            maxWidth: 640,
            minHeight: 360,
            idealHeight: 660,
            maxHeight: 660
        )
        .background(DS.bg)
        .background(shortcutRecorder)
    }

    private var generalTab: some View {
        panelStack {
            SWPageHeader(
                title: "通用设置",
                subtitle: "调整编辑体验、存储位置和主题",
                systemImage: "gearshape",
                tint: DS.primaryDeep
            )

            macPanel("编辑器") {
                SWSettingsRow("编辑字号", subtitle: "仅影响 mac 便利贴编辑器", systemImage: "textformat.size") {
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
                    }
                }

                SWRowDivider()

                SWSettingsRow("行高", subtitle: "控制编辑器正文的阅读密度", systemImage: "line.3.horizontal.decrease") {
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
                    }
                }

                SWRowDivider()

                toggleRow("复制时增加段落空行", subtitle: "粘贴到 Typora 等 Markdown 软件时更接近段落格式", systemImage: "doc.on.clipboard", isOn: $settings.copyAddsParagraphSpacing)

                SWRowDivider()

                toggleRow("关闭时自动删除空笔记", subtitle: "正文为空的便利贴关闭后直接移除", systemImage: "trash", isOn: $settings.autoDeleteEmptyNotes)
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
                tint: DS.link
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

                Button("恢复默认格式快捷键") {
                    shortcutStore.resetMarkdownShortcuts()
                    recordingAction = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                helperText(recordingAction == nil ? "点击录制后按下新的组合键；Esc 取消。" : "正在录制：按下新的组合键，或按 Esc 取消。")
            }
        }
    }

    private var keyTab: some View {
        panelStack {
            SWPageHeader(
                title: "密钥",
                subtitle: vaultStore.isKeyLoaded ? "这台 Mac 已经可以解锁加密笔记" : "加载密钥后才能查看加密笔记正文",
                systemImage: vaultStore.isKeyLoaded ? "checkmark.shield.fill" : "lock.shield",
                tint: vaultStore.isKeyLoaded ? DS.primaryDeep : DS.textSubtle
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

    private func panelStack<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        MacSettingsPage(content: content)
    }

    private func macPanel<Content: View>(
        _ title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        SWSectionPanel(title) {
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

private struct MacSettingsPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        contentStack
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DS.bg)
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: DS.s3) {
            content()
        }
        .padding(.top, DS.s3)
        .padding(.horizontal, DS.s3)
        .padding(.bottom, DS.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
