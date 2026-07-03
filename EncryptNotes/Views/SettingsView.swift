import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#endif

struct SettingsView: View {
    @Binding var isPresented: Bool
    @Binding var showTrash: Bool
    @StateObject private var vaultStore = VaultStore.shared
    @StateObject private var syncStore = SyncStatusStore.shared

    var body: some View {
        NavigationStack {
            SWPanelStack {
                statusHeader

                SWSectionPanel {
                    settingsLink("笔记与编辑器", subtitle: "默认模式、Markdown 与编辑行为", systemImage: "textformat") {
                        NotesSettingsView()
                    }
                    SWRowDivider()
                    settingsLink("密钥与加密", subtitle: "导入、导出、卸载或处理加密笔记", systemImage: "lock") {
                        KeyManagementView()
                    }
                    SWRowDivider()
                    settingsLink("隐私保护", subtitle: "后台隐藏与自动卸载密钥", systemImage: "hand.raised") {
                        PrivacySettingsView()
                    }
                    SWRowDivider()
                    settingsLink("数据", subtitle: "回收站、同步、导出与维护", systemImage: "externaldrive") {
                        DataSettingsView(showTrash: $showTrash, isPresented: $isPresented)
                    }
                    SWRowDivider()
                    settingsLink("外观", subtitle: "主题色与应用图标", systemImage: "paintpalette") {
                        AppearanceSettingsView()
                    }
                    SWRowDivider()
                    settingsLink("关于", subtitle: "版本、同步与安全说明", systemImage: "info.circle", tint: DS.link) {
                        AboutView()
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .dsLiquidGlassToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
        }
    }

    private var statusHeader: some View {
        SWSectionPanel {
            SWSettingsRow(
                vaultStore.isUsingICloudStorage ? "iCloud 同步空间" : "本地存储空间",
                subtitle: storageSubtitle,
                systemImage: vaultStore.isUsingICloudStorage ? "icloud" : "folder",
                tint: syncTint
            ) {
                syncTrailing
            }
        }
    }

    private var storageSubtitle: String {
        switch syncStore.status {
        case .syncing:
            return "正在读取和写入笔记文件"
        case .saved:
            return syncStore.isNetworkAvailable ? "笔记会通过 iCloud Drive 同步" : "当前网络不可用，稍后会继续同步"
        case .failed(let message):
            return message
        }
    }

    private var syncTint: Color {
        switch syncStore.status {
        case .failed:
            return DS.destructive
        case .syncing:
            return DS.pro
        case .saved:
            return vaultStore.isUsingICloudStorage ? DS.primaryDeep : DS.pro
        }
    }

    @ViewBuilder
    private var syncTrailing: some View {
        switch syncStore.status {
        case .syncing:
            ProgressView()
                .controlSize(.small)
        case .saved:
            SWStatusBadge(syncStore.isNetworkAvailable ? "可用" : "离线", style: syncStore.isNetworkAvailable ? .success : .warning)
        case .failed:
            Button("重试") {
                Task { await vaultStore.refreshFromStorage() }
            }
            .font(DS.caption())
        }
    }

    private func settingsLink<Destination: View>(
        _ title: String,
        subtitle: String,
        systemImage: String,
        tint: Color = DS.primaryDeep,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            SWSettingsRow(title, subtitle: subtitle, systemImage: systemImage, tint: tint) {
                HStack(spacing: DS.s2) {
                    if title == "数据", vaultStore.trashCount > 0 {
                        SWStatusBadge("\(vaultStore.trashCount)", style: .neutral)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.textSubtle)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct NotesSettingsView: View {
    @StateObject private var vaultStore = VaultStore.shared
    @StateObject private var settings = SettingsStore.shared

    var body: some View {
        SWPanelStack {
            SWSectionPanel("新建笔记", footer: "当前没有密钥时，新建笔记会保持为明文。") {
                SWSettingsRow("默认创建加密笔记", subtitle: vaultStore.isKeyLoaded ? "新建笔记会默认打开加密" : "需要先创建或导入密钥", systemImage: "lock") {
                    Toggle("", isOn: defaultEncryptedBinding)
                        .labelsHidden()
                        .tint(DS.primary)
                        .disabled(!vaultStore.isKeyLoaded)
                }
            }

            SWSectionPanel("Markdown") {
                SWSettingsRow("编辑器格式工具栏", subtitle: "可快速插入粗体、斜体、代码和链接", systemImage: "character.cursor.ibeam") {
                    SWStatusBadge("已开启", style: .success)
                }
                SWRowDivider()
                SWSettingsRow("Markdown 预览", subtitle: "在编辑器右上角切换预览", systemImage: "play.rectangle") {
                    SWStatusBadge("已开启", style: .success)
                }
            }
        }
        .navigationTitle("笔记与编辑器")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var defaultEncryptedBinding: Binding<Bool> {
        Binding(
            get: { settings.preferredNoteMode == .encrypted },
            set: { settings.preferredNoteMode = $0 && vaultStore.isKeyLoaded ? .encrypted : .plain }
        )
    }
}

private struct KeyManagementView: View {
    @StateObject private var vaultStore = VaultStore.shared
    @State private var showKeyImporter = false
    @State private var exportedKeyURL: URL?
    @State private var showShareSheet = false
    @State private var showUnloadConfirmation = false
    @State private var showResetFirstConfirmation = false
    @State private var showResetSecondConfirmation = false
    @State private var showDeleteEncryptedConfirmation = false
    @State private var showDecryptAllConfirmation = false
    @State private var showExportPlaintextConfirmation = false
    @State private var exportedPlaintextURL: URL?
    @State private var operationMessage: String?
    @State private var showOperationResult = false

    var body: some View {
        SWPanelStack {
            SWSectionPanel {
                SWSettingsRow(
                    "密钥状态",
                    subtitle: vaultStore.isKeyLoaded ? "这台设备可以查看加密笔记" : "加密笔记会保持锁定状态",
                    systemImage: vaultStore.isKeyLoaded ? "lock.open.fill" : "lock.fill",
                    tint: vaultStore.isKeyLoaded ? DS.primaryDeep : DS.textSubtle
                ) {
                    SWStatusBadge(vaultStore.isKeyLoaded ? "已加载" : "未加载", style: vaultStore.isKeyLoaded ? .success : .neutral)
                }
            }

            if vaultStore.isKeyLoaded {
                loadedKeyActions
                advancedKeyActions
            } else {
                unloadedKeyActions
            }

            SWSectionPanel("危险操作", footer: "重置密钥将删除所有加密笔记，明文笔记会保留。") {
                Button(role: .destructive) {
                    showResetFirstConfirmation = true
                } label: {
                    SWSettingsRow("重置密钥", subtitle: "删除所有加密笔记并生成新密钥", systemImage: "trash", tint: DS.destructive) {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("密钥与加密")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showKeyImporter,
            allowedContentTypes: [UTType(filenameExtension: "snkey") ?? .json],
            allowsMultipleSelection: false
        ) { result in
            handleKeyImport(result)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedPlaintextURL ?? exportedKeyURL {
                ShareSheet(items: [url])
            }
        }
        .alert("操作结果", isPresented: $showOperationResult) {
            Button("确定") { operationMessage = nil }
        } message: {
            Text(operationMessage ?? "")
        }
        .alert("卸载本机密钥", isPresented: $showUnloadConfirmation) {
            Button("取消", role: .cancel) {}
            Button("继续卸载", role: .destructive) {
                Task { await unloadKey() }
            }
        } message: {
            Text("卸载后，这台设备将无法查看加密笔记内容。\n你可以稍后重新导入密钥恢复查看。\n建议先导出并保存密钥。")
        }
        .alert("全部转为明文？", isPresented: $showDecryptAllConfirmation) {
            Button("取消", role: .cancel) {}
            Button("转为明文", role: .destructive) {
                Task { await decryptAllEncryptedNotes() }
            }
        } message: {
            Text("所有加密笔记会写回为明文文件，并移除本机密钥。敏感内容将不再加密。")
        }
        .alert("导出解密内容并移除本地加密笔记？", isPresented: $showExportPlaintextConfirmation) {
            Button("取消", role: .cancel) {}
            Button("导出并移除", role: .destructive) {
                Task { await exportPlaintextAndRemoveEncryptedNotes() }
            }
        } message: {
            Text("导出的 zip 包包含明文内容。导出成功后，本地加密笔记会被永久移除。")
        }
        .alert("永久删除所有加密笔记？", isPresented: $showDeleteEncryptedConfirmation) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) {
                Task { await permanentlyDeleteEncryptedNotes() }
            }
        } message: {
            Text("这个操作不会移到回收站，删除后无法恢复。明文笔记会保留。")
        }
        .alert("重置密钥", isPresented: $showResetFirstConfirmation) {
            Button("取消", role: .cancel) {}
            Button("继续", role: .destructive) { showResetSecondConfirmation = true }
        } message: {
            Text("重置密钥将删除所有加密笔记，包括回收站中的加密笔记。\n明文笔记会保留。\n如果你还需要旧加密笔记，请先确认自己保存了旧密钥。")
        }
        .alert("最终确认", isPresented: $showResetSecondConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重置密钥", role: .destructive) {
                Task { await resetKey() }
            }
        } message: {
            Text("确定要删除所有加密笔记并生成新密钥吗？此操作不可撤销。")
        }
    }

    private var loadedKeyActions: some View {
        SWSectionPanel("密钥操作") {
            Button {
                exportKeyFile()
            } label: {
                SWSettingsRow("导出密钥", subtitle: "保存当前密钥", systemImage: "square.and.arrow.up") {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
            SWRowDivider()
            Button(role: .destructive) {
                showUnloadConfirmation = true
            } label: {
                SWSettingsRow("卸载本机密钥", subtitle: "不删除笔记，只让加密内容回到锁定状态", systemImage: "lock.slash", tint: DS.destructive) {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var advancedKeyActions: some View {
        SWSectionPanel("加密笔记处理", footer: "这些操作会改变现有加密笔记，请先确认密钥已妥善保存。") {
            Button {
                showDecryptAllConfirmation = true
            } label: {
                SWSettingsRow("全部转为明文", subtitle: "解密所有加密笔记并移除本机密钥", systemImage: "lock.open") {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
            SWRowDivider()
            Button {
                showExportPlaintextConfirmation = true
            } label: {
                SWSettingsRow("解密导出并移除本地", subtitle: "导出明文 zip 后永久移除本地加密笔记", systemImage: "archivebox") {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
            SWRowDivider()
            Button(role: .destructive) {
                showDeleteEncryptedConfirmation = true
            } label: {
                SWSettingsRow("永久删除所有加密笔记", subtitle: "不进入回收站，无法恢复", systemImage: "trash", tint: DS.destructive) {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var unloadedKeyActions: some View {
        SWSectionPanel("密钥操作", footer: "密钥只会在本机读取，不会上传。") {
            Button {
                Task { await createKey() }
            } label: {
                SWSettingsRow("创建密钥", subtitle: "为这台设备生成新的加密密钥", systemImage: "key.fill") {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
            SWRowDivider()
            Button {
                showKeyImporter = true
            } label: {
                SWSettingsRow("导入密钥", subtitle: "加载已有密钥", systemImage: "square.and.arrow.down") {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func createKey() async {
        do { try await vaultStore.createKey() }
        catch { vaultStore.lastError = "创建密钥失败：\(error.localizedDescription)" }
    }

    private func unloadKey() async {
        do { try await vaultStore.unloadKey() }
        catch { vaultStore.lastError = "卸载密钥失败：\(error.localizedDescription)" }
    }

    private func resetKey() async {
        do { try await vaultStore.resetKey() }
        catch { vaultStore.lastError = "重置密钥失败：\(error.localizedDescription)" }
    }

    private func decryptAllEncryptedNotes() async {
        do {
            let count = try await vaultStore.decryptAllEncryptedNotesAndRemoveKey()
            operationMessage = "已将 \(count) 条加密笔记转为明文。"
            showOperationResult = true
        } catch {
            vaultStore.lastError = "转为明文失败：\(error.localizedDescription)"
        }
    }

    private func exportPlaintextAndRemoveEncryptedNotes() async {
        do {
            let result = try await vaultStore.exportPlaintextEncryptedNotesAndRemoveLocalNotes()
            exportedPlaintextURL = result.url
            exportedKeyURL = nil
            showShareSheet = true
        } catch {
            vaultStore.lastError = "导出失败：\(error.localizedDescription)"
        }
    }

    private func permanentlyDeleteEncryptedNotes() async {
        do {
            let count = try await vaultStore.permanentlyDeleteAllEncryptedNotes()
            operationMessage = "已永久删除 \(count) 条加密笔记。"
            showOperationResult = true
        } catch {
            vaultStore.lastError = "删除失败：\(error.localizedDescription)"
        }
    }

    private func exportKeyFile() {
        do {
            exportedKeyURL = try vaultStore.exportKeyFile()
            exportedPlaintextURL = nil
            vaultStore.needsKeyExport = false
            showShareSheet = true
        } catch {
            vaultStore.lastError = "导出密钥失败：\(error.localizedDescription)"
        }
    }

    private func handleKeyImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do { _ = try await vaultStore.importKeyFile(from: url) }
                catch { vaultStore.lastError = "导入密钥失败：\(error.localizedDescription)" }
            }
        case .failure:
            break
        }
    }
}

private struct PrivacySettingsView: View {
    @StateObject private var settings = SettingsStore.shared

    var body: some View {
        SWPanelStack {
            SWSectionPanel("隐私保护", footer: "自动卸载密钥不会删除笔记，只会让加密笔记回到乱码状态。") {
                SWSettingsRow("进入后台时隐藏内容", subtitle: "切换到其他应用时遮住笔记内容", systemImage: "eye.slash") {
                    Toggle("", isOn: $settings.hideContentOnBackground)
                        .labelsHidden()
                        .tint(DS.primary)
                }
                SWRowDivider()
                SWSettingsRow("重新打开 App 时自动卸载密钥", subtitle: "再次进入 App 后需要重新导入密钥", systemImage: "lock.rotation") {
                    Toggle("", isOn: $settings.autoUnloadKeyOnForeground)
                        .labelsHidden()
                        .tint(DS.primary)
                }
            }
        }
        .navigationTitle("隐私保护")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DataSettingsView: View {
    @Binding var showTrash: Bool
    @Binding var isPresented: Bool
    @StateObject private var vaultStore = VaultStore.shared
    @StateObject private var syncStore = SyncStatusStore.shared
    @StateObject private var settings = SettingsStore.shared
    @State private var showEmptyConfirmation = false
    @State private var showClearEmptyConfirmation = false
    @State private var exportedNotesURL: URL?
    @State private var exportedLogURL: URL?
    @State private var showShareSheet = false
    @State private var operationMessage: String?
    @State private var showOperationResult = false

    var body: some View {
        SWPanelStack {
            SWSectionPanel("同步") {
                SWSettingsRow(syncTitle, subtitle: syncSubtitle, systemImage: syncIcon, tint: syncTint) {
                    Button("刷新") {
                        Task { await vaultStore.refreshFromStorage() }
                    }
                    .font(DS.caption())
                }
            }

            SWSectionPanel("回收站", footer: "回收站笔记将在删除 30 天后自动永久删除。") {
                Button {
                    isPresented = false
                    showTrash = true
                } label: {
                    SWSettingsRow("查看回收站", subtitle: "恢复或永久删除已移除笔记", systemImage: "trash", tint: DS.destructive) {
                        if vaultStore.trashCount > 0 {
                            SWStatusBadge("\(vaultStore.trashCount)", style: .neutral)
                        }
                    }
                }
                .buttonStyle(.plain)
                SWRowDivider()
                Button {
                    Task { await vaultStore.purgeExpiredTrash() }
                } label: {
                    SWSettingsRow("清理 30 天前删除的笔记", subtitle: "只移除已经到期的回收站笔记", systemImage: "clock.arrow.circlepath") {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
                SWRowDivider()
                Button(role: .destructive) {
                    showEmptyConfirmation = true
                } label: {
                    SWSettingsRow("清空回收站", subtitle: "永久删除回收站中的所有笔记", systemImage: "trash.slash", tint: DS.destructive) {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
            }

            SWSectionPanel("导出与维护") {
                Button {
                    exportReadableNotes()
                } label: {
                    SWSettingsRow("导出明文笔记", subtitle: "导出 zip，跳过加密笔记", systemImage: "square.and.arrow.up") {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
                SWRowDivider()
                Button(role: .destructive) {
                    showClearEmptyConfirmation = true
                } label: {
                    SWSettingsRow("清理空白笔记", subtitle: "将正文为空的可读笔记移到回收站", systemImage: "trash", tint: DS.destructive) {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
                SWRowDivider()
                SWSettingsRow("记录维护日志", subtitle: "不记录正文或密钥", systemImage: "doc.text.magnifyingglass") {
                    Toggle("", isOn: $settings.maintenanceLoggingEnabled)
                        .labelsHidden()
                        .tint(DS.primary)
                }
                SWRowDivider()
                Button {
                    exportMaintenanceLog()
                } label: {
                    SWSettingsRow("导出维护日志", subtitle: "用于问题排查", systemImage: "square.and.arrow.down") {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("数据")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedLogURL ?? exportedNotesURL {
                ShareSheet(items: [url])
            }
        }
        .alert("操作结果", isPresented: $showOperationResult) {
            Button("确定") { operationMessage = nil }
        } message: {
            Text(operationMessage ?? "")
        }
        .alert("清空回收站", isPresented: $showEmptyConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                Task {
                    do { try await vaultStore.emptyTrash() }
                    catch { vaultStore.lastError = "清空失败：\(error.localizedDescription)" }
                }
            }
        } message: {
            Text("将永久删除回收站中的所有笔记，无法恢复。")
        }
        .alert("清理空白笔记", isPresented: $showClearEmptyConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) {
                Task { await clearEmptyNotes() }
            }
        } message: {
            Text("正文为空的可读笔记会移到回收站，可以恢复。")
        }
    }

    private var syncTitle: String {
        switch syncStore.status {
        case .syncing: return "正在同步"
        case .saved: return syncStore.isNetworkAvailable ? "同步可用" : "网络离线"
        case .failed: return "同步失败"
        }
    }

    private var syncSubtitle: String {
        switch syncStore.status {
        case .syncing: return "正在读取和写入笔记文件"
        case .saved: return vaultStore.isUsingICloudStorage ? "当前使用 iCloud Drive" : "当前使用本地回退存储"
        case .failed(let message): return message
        }
    }

    private var syncIcon: String {
        switch syncStore.status {
        case .failed: return "exclamationmark.icloud"
        case .saved: return syncStore.isNetworkAvailable ? "icloud" : "icloud.slash"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        }
    }

    private var syncTint: Color {
        switch syncStore.status {
        case .failed: return DS.destructive
        case .syncing: return DS.pro
        case .saved: return DS.primaryDeep
        }
    }

    private func exportReadableNotes() {
        do {
            let result = try vaultStore.exportReadableNotesAsZip()
            exportedNotesURL = result.url
            exportedLogURL = nil
            showShareSheet = true
            if result.skippedCount > 0 {
                operationMessage = "导出 \(result.exportedCount) 条明文笔记，跳过 \(result.skippedCount) 条加密笔记。"
                showOperationResult = true
            }
        } catch {
            vaultStore.lastError = "导出失败：\(error.localizedDescription)"
        }
    }

    private func exportMaintenanceLog() {
        do {
            exportedLogURL = try MaintenanceLogStore.shared.exportLogFile()
            exportedNotesURL = nil
            showShareSheet = true
        } catch {
            vaultStore.lastError = "导出日志失败：\(error.localizedDescription)"
        }
    }

    private func clearEmptyNotes() async {
        do {
            let count = try await vaultStore.clearEmptyReadableNotes()
            operationMessage = count == 0 ? "没有需要清理的空白笔记。" : "已将 \(count) 条空白笔记移到回收站。"
            showOperationResult = true
        } catch {
            vaultStore.lastError = "清理失败：\(error.localizedDescription)"
        }
    }
}

private struct AppearanceSettingsView: View {
    @StateObject private var settings = SettingsStore.shared
    @State private var pendingIcon: IOSAppIconChoice?
    @State private var showIconConfirmation = false

    var body: some View {
        SWPanelStack {
            SWSectionPanel("主题色") {
                ForEach(Array(MacTheme.allCases.enumerated()), id: \.element.id) { index, theme in
                    Button {
                        settings.macTheme = theme
                    } label: {
                        SWSettingsRow(theme.title, subtitle: themeSubtitle(theme), systemImage: theme == settings.macTheme ? "checkmark.circle.fill" : "circle", tint: tint(for: theme)) {
                            themeSwatch(theme)
                        }
                    }
                    .buttonStyle(.plain)
                    if index < MacTheme.allCases.count - 1 {
                        SWRowDivider()
                    }
                }
            }

            #if os(iOS)
            SWSectionPanel("应用图标", footer: "更换图标时，iOS 会显示系统确认弹窗。主题色和图标可以独立选择。") {
                ForEach(Array(IOSAppIconChoice.allCases.enumerated()), id: \.element.id) { index, choice in
                    Button {
                        pendingIcon = choice
                        showIconConfirmation = true
                    } label: {
                        SWSettingsRow(choice.title, subtitle: iconSubtitle(choice), systemImage: choice == currentIconChoice ? "checkmark.circle.fill" : "app", tint: iconTint(choice)) {
                            iconSwatch(choice)
                        }
                    }
                    .buttonStyle(.plain)
                    if index < IOSAppIconChoice.allCases.count - 1 {
                        SWRowDivider()
                    }
                }
            }
            .alert("更换应用图标？", isPresented: $showIconConfirmation) {
                Button("取消", role: .cancel) { pendingIcon = nil }
                Button("更换") {
                    applyPendingIcon()
                }
            } message: {
                Text("主屏幕上的 Seal Note 图标会改变。接下来 iOS 还会显示一次系统确认。")
            }
            #endif
        }
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func themeSubtitle(_ theme: MacTheme) -> String? {
        theme == settings.macTheme ? "当前主题色" : nil
    }

    private func tint(for theme: MacTheme) -> Color {
        switch theme {
        case .pink: return Color(light: 0x8F2D5A, dark: 0xFFD8E8)
        case .cyan: return Color(light: 0x246A73, dark: 0xCFF7FB)
        case .green: return Color(light: 0x397354, dark: 0xD4D4D4)
        }
    }

    private func themeSwatch(_ theme: MacTheme) -> some View {
        Circle()
            .fill(tint(for: theme))
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(DS.line, lineWidth: 0.5))
    }

    #if os(iOS)
    private var currentIconChoice: IOSAppIconChoice {
        IOSAppIconChoice.choice(for: settings.iOSAppIconName)
    }

    private func iconSubtitle(_ choice: IOSAppIconChoice) -> String? {
        choice == currentIconChoice ? "当前图标" : nil
    }

    private func iconTint(_ choice: IOSAppIconChoice) -> Color {
        switch choice {
        case .primary: return tint(for: .pink)
        case .cyan: return tint(for: .cyan)
        case .green: return tint(for: .green)
        }
    }

    private func iconSwatch(_ choice: IOSAppIconChoice) -> some View {
        RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
            .fill(iconTint(choice))
            .frame(width: 24, height: 24)
            .overlay(
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            )
    }

    private func applyPendingIcon() {
        guard let pendingIcon else { return }
        guard UIApplication.shared.supportsAlternateIcons else {
            settings.iOSAppIconName = pendingIcon.iconName
            self.pendingIcon = nil
            return
        }
        UIApplication.shared.setAlternateIconName(pendingIcon.iconName) { error in
            Task { @MainActor in
                if error == nil {
                    settings.iOSAppIconName = pendingIcon.iconName
                }
                self.pendingIcon = nil
            }
        }
    }
    #endif
}

private struct AboutView: View {
    var body: some View {
        SWPanelStack {
            SWSectionPanel {
                SWSettingsRow("应用名称", systemImage: "app.badge") {
                    Text("Seal Note")
                }
                SWRowDivider()
                SWSettingsRow("当前版本", systemImage: "number") {
                    Text("v0.2")
                }
            }

            SWSectionPanel("说明") {
                SWSettingsRow("iCloud 同步", subtitle: "笔记文件保存在 iCloud Drive 中，可在多设备间同步。", systemImage: "icloud") {
                    EmptyView()
                }
                SWRowDivider()
                SWSettingsRow("内容安全", subtitle: "明文笔记不会加密，敏感内容建议使用加密笔记。", systemImage: "shield") {
                    EmptyView()
                }
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}
