import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#endif

enum SettingsRoute: Hashable {
    case notes
    case key
    case privacy
    case data
    case appearance
    case about
}

struct SettingsView: View {
    @Binding var isPresented: Bool
    @Binding var showTrash: Bool
    @StateObject private var vaultStore = VaultStore.shared
    @State private var path: [SettingsRoute]

    init(
        isPresented: Binding<Bool>,
        showTrash: Binding<Bool>,
        initialRoute: SettingsRoute? = nil
    ) {
        _isPresented = isPresented
        _showTrash = showTrash
        _path = State(initialValue: initialRoute.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            SWPanelStack {
                SWSectionPanel {
                    settingsLink(.notes, "笔记与编辑器", subtitle: "默认模式、Markdown 与编辑行为", systemImage: "textformat", tint: DS.ai)
                    SWRowDivider()
                    settingsLink(.key, "密钥与加密", subtitle: "创建、导入、移除或处理加密笔记", systemImage: "lock", tint: DS.primaryDeep)
                    SWRowDivider()
                    settingsLink(.privacy, "隐私保护", subtitle: "后台隐藏与本机密钥保护", systemImage: "hand.raised", tint: DS.pro)
                    SWRowDivider()
                    settingsLink(.data, "数据", subtitle: "回收站、同步、导出与维护", systemImage: "externaldrive", tint: DS.link)
                    SWRowDivider()
                    settingsLink(.appearance, "外观", subtitle: "主题色与应用图标", systemImage: "paintpalette", tint: DS.primaryDeep)
                    SWRowDivider()
                    settingsLink(.about, "关于", subtitle: "版本、同步与安全说明", systemImage: "info.circle", tint: DS.link)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .notes:
                    NotesSettingsView()
                case .key:
                    KeyManagementView()
                case .privacy:
                    PrivacySettingsView()
                case .data:
                    DataSettingsView(showTrash: $showTrash, isPresented: $isPresented)
                case .appearance:
                    AppearanceSettingsView()
                case .about:
                    AboutView()
                }
            }
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

    private func settingsLink(
        _ route: SettingsRoute,
        _ title: String,
        subtitle: String,
        systemImage: String,
        tint: Color = DS.primaryDeep
    ) -> some View {
        NavigationLink(value: route) {
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
                SWSettingsRow("默认创建加密笔记", subtitle: vaultStore.isKeyLoaded ? "新建笔记会默认打开加密" : "需要先在密钥设置中创建或加载密钥", systemImage: "lock") {
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
    private enum LocalKeyStatus: Equatable {
        case noReference
        case available
        case invalid(VaultKeyFileError)
    }

    private enum KeyAlert: Equatable {
        case removeNoEncrypted
        case removeUsableEncrypted
        case removeInvalidEncrypted
        case createDeletesEncrypted
        case mismatchedImport
        case deleteEncrypted
        case decryptAll
        case exportPlaintext
    }

    @StateObject private var vaultStore = VaultStore.shared
    @State private var showKeyImporter = false
    @State private var exportedKeyURL: URL?
    @State private var showShareSheet = false
    @State private var exportedPlaintextURL: URL?
    @State private var operationMessage: String?
    @State private var showOperationResult = false
    @State private var activeAlert: KeyAlert?
    @State private var pendingImportURL: URL?

    var body: some View {
        SWPanelStack {
            SWSectionPanel {
                SWSettingsRow(
                    keyStatusTitle,
                    subtitle: keyStatusSubtitle,
                    systemImage: keyStatusIcon,
                    tint: keyStatusTint
                ) {
                    keyManagementActions
                }
            }

            if vaultStore.isKeyLoaded {
                loadedKeyActions
            }

            if vaultStore.encryptedEntryCount > 0 {
                encryptedNotesActions
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
        .alert(activeAlertTitle, isPresented: activeAlertBinding) {
            activeAlertActions
        } message: {
            Text(activeAlertMessage)
        }
    }

    private var keyStatus: LocalKeyStatus {
        #if os(iOS)
        switch vaultStore.iosKeyStatus {
        case .noReference:
            return .noReference
        case .available:
            return .available
        case .invalid(let error):
            return .invalid(error)
        }
        #else
        return vaultStore.isKeyLoaded ? .available : .noReference
        #endif
    }

    private var keyStatusTitle: String {
        switch keyStatus {
        case .noReference:
            return "未加载本机密钥"
        case .available:
            return "本机密钥已加载"
        case .invalid(.keyReplaced):
            return "本机密钥已被替换"
        case .invalid:
            return "本机密钥失效"
        }
    }

    private var keyStatusSubtitle: String {
        let encryptedCount = vaultStore.encryptedEntryCount
        switch keyStatus {
        case .noReference where encryptedCount > 0:
            return "发现 \(encryptedCount) 条加密笔记，请优先加载原密钥。"
        case .noReference:
            return "当前未加载密钥。密钥只会保存到本机 Keychain。"
        case .available:
            return encryptedCount > 0
                ? "这台设备可以查看加密笔记，请确认已导出并保存密钥。"
                : "这台设备可以创建和查看加密笔记，请导出并妥善保存密钥。"
        case .invalid(let error) where encryptedCount > 0:
            return "\(error.localizedDescription)\n\(encryptedCount) 条加密笔记需要原密钥解锁。"
        case .invalid(let error):
            return error.localizedDescription
        }
    }

    private var keyStatusIcon: String {
        switch keyStatus {
        case .noReference:
            return "lock.shield"
        case .available:
            return "checkmark.shield.fill"
        case .invalid:
            return "exclamationmark.triangle"
        }
    }

    private var keyStatusTint: Color {
        switch keyStatus {
        case .noReference:
            return DS.textSubtle
        case .available:
            return DS.primaryDeep
        case .invalid:
            return DS.destructive
        }
    }

    @ViewBuilder
    private var keyManagementActions: some View {
        switch keyStatus {
        case .noReference:
            if vaultStore.encryptedEntryCount > 0 {
                HStack(spacing: DS.s2) {
                    smallActionButton("加载", prominent: true) { showKeyImporter = true }
                    smallActionButton("创建") { createKey() }
                }
            } else {
                HStack(spacing: DS.s2) {
                    smallActionButton("创建", prominent: true) { createKey() }
                    smallActionButton("加载") { showKeyImporter = true }
                }
            }
        case .available:
            HStack(spacing: DS.s2) {
                smallActionButton("导出") { exportKeyFile() }
                smallActionButton("移除", destructive: true) { removeKeyReference() }
            }
        case .invalid:
            HStack(spacing: DS.s2) {
                smallActionButton("重新导入", prominent: true) { showKeyImporter = true }
                smallActionButton("移除", destructive: true) { removeKeyReference() }
            }
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
                removeKeyReference()
            } label: {
                SWSettingsRow("移除本机密钥", subtitle: "移除前需要先处理所有加密笔记", systemImage: "lock.slash", tint: DS.destructive) {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var encryptedNotesActions: some View {
        SWSectionPanel("加密笔记处理", footer: affectedEncryptedNotesMessage(prefix: "这些操作会改变现有加密笔记，请先确认密钥已妥善保存。")) {
            if keyStatus == .available {
                Button {
                    activeAlert = .decryptAll
                } label: {
                    SWSettingsRow("全部转为明文", subtitle: "解密所有加密笔记并移除本机密钥", systemImage: "lock.open") {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
                SWRowDivider()
                Button {
                    activeAlert = .exportPlaintext
                } label: {
                    SWSettingsRow("解密导出并移除本地", subtitle: "导出明文 zip 后永久移除本地加密笔记", systemImage: "archivebox") {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
                SWRowDivider()
            }
            Button(role: .destructive) {
                activeAlert = .deleteEncrypted
            } label: {
                SWSettingsRow("永久删除所有加密笔记", subtitle: "不进入回收站，无法恢复", systemImage: "trash", tint: DS.destructive) {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func smallActionButton(
        _ title: String,
        prominent: Bool = false,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(title, action: action)
                .font(DS.caption())
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(destructive ? DS.destructive : DS.primary)
        } else {
            Button(title, action: action)
                .font(DS.caption())
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(destructive ? DS.destructive : DS.primary)
        }
    }

    private func createKey() {
        if vaultStore.encryptedEntryCount > 0 {
            activeAlert = .createDeletesEncrypted
            return
        }
        Task { await createKeyDirectly() }
    }

    private func createKeyDirectly() async {
        do { try await vaultStore.createKey() }
        catch { vaultStore.lastError = "创建密钥失败：\(error.localizedDescription)" }
    }

    private func removeKeyReference() {
        if vaultStore.encryptedEntryCount == 0 {
            activeAlert = .removeNoEncrypted
            return
        }

        switch keyStatus {
        case .available:
            activeAlert = .removeUsableEncrypted
        case .invalid:
            activeAlert = .removeInvalidEncrypted
        case .noReference:
            activeAlert = .deleteEncrypted
        }
    }

    private func unloadKey() async {
        do {
            try await vaultStore.unloadKey()
            operationMessage = "已移除本机密钥。"
            showOperationResult = true
        } catch {
            vaultStore.lastError = "移除密钥失败：\(error.localizedDescription)"
        }
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

    private func deleteEncryptedNotesAndCreateKey() async {
        do {
            _ = try await vaultStore.permanentlyDeleteAllEncryptedNotes()
            try await vaultStore.createKey()
            operationMessage = "已删除全部加密笔记，并创建新密钥。"
            showOperationResult = true
        } catch {
            vaultStore.lastError = "创建密钥失败：\(error.localizedDescription)"
        }
    }

    private func deleteEncryptedNotesAndImportPendingKey(from url: URL) async {
        do {
            _ = try await vaultStore.permanentlyDeleteAllEncryptedNotes()
            _ = try await vaultStore.importKeyFile(from: url)
            self.pendingImportURL = nil
            operationMessage = "已删除原加密笔记，并加载所选密钥。"
            showOperationResult = true
        } catch {
            vaultStore.lastError = "导入密钥失败：\(error.localizedDescription)"
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
            Task { @MainActor in
                do {
                    _ = try await vaultStore.importKeyFile(from: url)
                } catch {
                    if let keyError = error as? VaultKeyFileError, keyError == .keyMismatch {
                        pendingImportURL = url
                        activeAlert = .mismatchedImport
                    } else {
                        vaultStore.lastError = "导入密钥失败：\(error.localizedDescription)"
                    }
                }
            }
        case .failure:
            pendingImportURL = nil
            break
        }
    }

    private var activeAlertBinding: Binding<Bool> {
        Binding(
            get: { activeAlert != nil },
            set: { isPresented in
                if !isPresented {
                    if activeAlert == .mismatchedImport {
                        pendingImportURL = nil
                    }
                    activeAlert = nil
                }
            }
        )
    }

    private var activeAlertTitle: String {
        switch activeAlert {
        case .removeNoEncrypted:
            return "移除本机密钥？"
        case .removeUsableEncrypted:
            return "移除本机密钥前如何处理加密笔记？"
        case .removeInvalidEncrypted:
            return "密钥失效时移除本机密钥？"
        case .createDeletesEncrypted:
            return "创建新密钥会影响已有加密笔记"
        case .mismatchedImport:
            return "所选密钥无法解锁现有加密笔记"
        case .deleteEncrypted:
            return "永久删除所有加密笔记？"
        case .decryptAll:
            return "全部转为明文？"
        case .exportPlaintext:
            return "导出解密内容并移除本地加密笔记？"
        case nil:
            return ""
        }
    }

    private var activeAlertMessage: String {
        switch activeAlert {
        case .removeNoEncrypted:
            return "只会让 Seal Note 忘记这台设备上的密钥，不会删除你已经导出的 .snkey 文件。"
        case .removeUsableEncrypted:
            return affectedEncryptedNotesMessage(prefix: "移除本机密钥前，需要先删除这些加密笔记，或全部解密为明文。")
        case .removeInvalidEncrypted:
            return affectedEncryptedNotesMessage(prefix: "当前密钥不可用，无法在此时解密加密笔记。若仍保留原密钥，请取消并先重新导入密钥。")
        case .createDeletesEncrypted:
            return affectedEncryptedNotesMessage(prefix: "新密钥无法解锁现有加密笔记。继续前必须删除这些加密笔记。")
        case .mismatchedImport:
            return affectedEncryptedNotesMessage(prefix: "默认不会保存这次选择的密钥。")
        case .deleteEncrypted:
            return affectedEncryptedNotesMessage(prefix: "这个操作不会移到回收站，删除后无法恢复。明文笔记会保留。")
        case .decryptAll:
            return "所有加密笔记会写回为明文文件，并移除本机密钥。敏感内容将不再加密。"
        case .exportPlaintext:
            return "导出的 zip 包包含明文内容。导出成功后，本地加密笔记会被永久移除，并移除本机密钥。"
        case nil:
            return ""
        }
    }

    @ViewBuilder
    private var activeAlertActions: some View {
        switch activeAlert {
        case .removeNoEncrypted:
            Button("取消", role: .cancel) {}
            Button("移除本机密钥", role: .destructive) {
                Task { await unloadKey() }
            }
        case .removeUsableEncrypted:
            Button("删除全部加密笔记", role: .destructive) {
                Task { await permanentlyDeleteEncryptedNotes() }
            }
            Button("先全部解密成明文") {
                Task { await decryptAllEncryptedNotes() }
            }
            Button("取消", role: .cancel) {}
        case .removeInvalidEncrypted:
            Button("删除全部加密笔记", role: .destructive) {
                Task { await permanentlyDeleteEncryptedNotes() }
            }
            Button("取消", role: .cancel) {}
        case .createDeletesEncrypted:
            Button("删除这些加密笔记并创建新密钥", role: .destructive) {
                Task { await deleteEncryptedNotesAndCreateKey() }
            }
            Button("取消", role: .cancel) {}
        case .mismatchedImport:
            Button("重新选择密钥") {
                pendingImportURL = nil
                showKeyImporter = true
            }
            Button("删除这些加密笔记并使用此密钥", role: .destructive) {
                if let url = pendingImportURL {
                    Task { await deleteEncryptedNotesAndImportPendingKey(from: url) }
                }
            }
            Button("取消", role: .cancel) {
                pendingImportURL = nil
            }
        case .deleteEncrypted:
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) {
                Task { await permanentlyDeleteEncryptedNotes() }
            }
        case .decryptAll:
            Button("取消", role: .cancel) {}
            Button("转为明文", role: .destructive) {
                Task { await decryptAllEncryptedNotes() }
            }
        case .exportPlaintext:
            Button("取消", role: .cancel) {}
            Button("导出并移除", role: .destructive) {
                Task { await exportPlaintextAndRemoveEncryptedNotes() }
            }
        case nil:
            EmptyView()
        }
    }

    private func affectedEncryptedNotesMessage(prefix: String) -> String {
        "\(prefix)\n\n受影响范围包括当前列表和回收站中的 \(vaultStore.encryptedEntryCount) 条加密笔记。"
    }
}

private struct PrivacySettingsView: View {
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var vaultStore = VaultStore.shared

    var body: some View {
        SWPanelStack {
            SWSectionPanel("隐私保护", footer: privacyFooter) {
                SWSettingsRow("进入后台时隐藏内容", subtitle: "切换到其他应用时遮住笔记内容", systemImage: "eye.slash") {
                    Toggle("", isOn: $settings.hideContentOnBackground)
                        .labelsHidden()
                        .tint(DS.primary)
                }
                SWRowDivider()
                SWSettingsRow("重新打开 App 时自动移除本机密钥", subtitle: autoUnloadKeySubtitle, systemImage: "lock.rotation") {
                    Toggle("", isOn: autoUnloadKeyBinding)
                        .labelsHidden()
                        .tint(DS.primary)
                        .disabled(vaultStore.encryptedEntryCount > 0)
                }
            }
        }
        .navigationTitle("隐私保护")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { disableAutoUnloadIfNeeded() }
        .onChange(of: vaultStore.encryptedEntryCount) { _, _ in
            disableAutoUnloadIfNeeded()
        }
    }

    private var autoUnloadKeyBinding: Binding<Bool> {
        Binding(
            get: { settings.autoUnloadKeyOnForeground && vaultStore.encryptedEntryCount == 0 },
            set: { settings.autoUnloadKeyOnForeground = $0 && vaultStore.encryptedEntryCount == 0 }
        )
    }

    private var autoUnloadKeySubtitle: String {
        if vaultStore.encryptedEntryCount > 0 {
            return "存在加密笔记时不可自动移除"
        }
        return "再次进入 App 后会移除本机 Keychain 中的密钥"
    }

    private var privacyFooter: String {
        if vaultStore.encryptedEntryCount > 0 {
            return "移除本机密钥前，需要先在“密钥与加密”中处理所有加密笔记。"
        }
        return "自动移除只会清掉这台设备上的本机密钥，不会删除已导出的 .snkey 文件。"
    }

    private func disableAutoUnloadIfNeeded() {
        if vaultStore.encryptedEntryCount > 0 {
            settings.autoUnloadKeyOnForeground = false
        }
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
