import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Binding var isPresented: Bool
    @Binding var showTrash: Bool
    @StateObject private var vaultStore = VaultStore.shared
    @StateObject private var settings = SettingsStore.shared

    var body: some View {
        NavigationStack {
            SWPanelStack {
                SWSectionPanel {
                    NavigationLink {
                        KeyManagementView()
                    } label: {
                        SWSettingsRow("密钥管理", subtitle: "导入、导出或重置保险库密钥", systemImage: "lock") {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    SWRowDivider()
                    NavigationLink {
                        PrivacySettingsView()
                    } label: {
                        SWSettingsRow("隐私保护", subtitle: "控制后台隐藏与自动卸载密钥", systemImage: "hand.raised") {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    SWRowDivider()
                    NavigationLink {
                        TrashSettingsView(showTrash: $showTrash, isPresented: $isPresented)
                    } label: {
                        SWSettingsRow("回收站设置", subtitle: "查看、清理或清空已删除笔记", systemImage: "trash", tint: DS.destructive) {
                            HStack(spacing: DS.s2) {
                                if vaultStore.trashCount > 0 {
                                    SWStatusBadge("\(vaultStore.trashCount)", style: .neutral)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    SWRowDivider()
                    NavigationLink {
                        AboutView()
                    } label: {
                        SWSettingsRow("关于", subtitle: "版本、同步与安全说明", systemImage: "info.circle", tint: DS.link) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .dsLiquidGlassToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) { isPresented = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
        }
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
                SWSectionPanel("密钥操作") {
                    Button {
                        exportKeyFile()
                    } label: {
                        SWSettingsRow("导出密钥", subtitle: "保存为 .bkwkey 文件", systemImage: "square.and.arrow.up") {
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
            } else {
                SWSectionPanel("密钥操作", footer: "密钥文件只会在本机读取，不会上传。") {
                    Button {
                        Task {
                            do { try await vaultStore.createKey() }
                            catch { vaultStore.lastError = "创建密钥失败：\(error.localizedDescription)" }
                        }
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
                        SWSettingsRow("导入密钥文件", subtitle: "加载已有 .bkwkey 文件", systemImage: "square.and.arrow.down") {
                            EmptyView()
                        }
                    }
                    .buttonStyle(.plain)
                }
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
        .navigationTitle("密钥管理")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showKeyImporter,
            allowedContentTypes: [UTType(filenameExtension: "bkwkey") ?? .json],
            allowsMultipleSelection: false
        ) { result in
            handleKeyImport(result)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedKeyURL {
                ShareSheet(items: [url])
            }
        }
        .alert("卸载本机密钥", isPresented: $showUnloadConfirmation) {
            Button("取消", role: .cancel) {}
            Button("继续卸载", role: .destructive) {
                Task {
                    do { try await vaultStore.unloadKey() }
                    catch { vaultStore.lastError = "卸载密钥失败：\(error.localizedDescription)" }
                }
            }
        } message: {
            Text("卸载后，这台设备将无法查看加密笔记内容。\n你可以稍后重新导入密钥恢复查看。\n建议先导出并保存密钥文件。")
        }
        .alert("重置密钥", isPresented: $showResetFirstConfirmation) {
            Button("取消", role: .cancel) {}
            Button("继续", role: .destructive) { showResetSecondConfirmation = true }
        } message: {
            Text("重置密钥将删除所有加密笔记，包括回收站中的加密笔记。\n明文笔记会保留。\n如果你还需要旧加密笔记，请先确认自己保存了旧密钥文件。")
        }
        .alert("最终确认", isPresented: $showResetSecondConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重置密钥", role: .destructive) {
                Task {
                    do { try await vaultStore.resetKey() }
                    catch { vaultStore.lastError = "重置密钥失败：\(error.localizedDescription)" }
                }
            }
        } message: {
            Text("确定要删除所有加密笔记并生成新密钥吗？此操作不可撤销。")
        }
    }

    private func exportKeyFile() {
        do {
            exportedKeyURL = try vaultStore.exportKeyFile()
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

private struct TrashSettingsView: View {
    @Binding var showTrash: Bool
    @Binding var isPresented: Bool
    @StateObject private var vaultStore = VaultStore.shared
    @State private var showEmptyConfirmation = false

    var body: some View {
        SWPanelStack {
            SWSectionPanel {
                Button {
                    isPresented = false
                    showTrash = true
                } label: {
                    SWSettingsRow("查看回收站", subtitle: "恢复或永久删除已移除笔记", systemImage: "trash", tint: DS.destructive) {
                        HStack(spacing: DS.s2) {
                            if vaultStore.trashCount > 0 {
                                SWStatusBadge("\(vaultStore.trashCount)", style: .neutral)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            SWSectionPanel("清理", footer: "回收站笔记将在删除 30 天后自动永久删除。") {
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
        }
        .navigationTitle("回收站设置")
        .navigationBarTitleDisplayMode(.inline)
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
    }
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
