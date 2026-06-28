import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Binding var isPresented: Bool
    @Binding var showTrash: Bool
    @StateObject private var vaultStore = VaultStore.shared
    @StateObject private var settings = SettingsStore.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        KeyManagementView()
                    } label: {
                        Label("密钥管理", systemImage: "lock")
                    }
                    NavigationLink {
                        PrivacySettingsView()
                    } label: {
                        Label("隐私保护", systemImage: "hand.raised")
                    }
                    NavigationLink {
                        TrashSettingsView(showTrash: $showTrash, isPresented: $isPresented)
                    } label: {
                        Label("回收站设置", systemImage: "trash")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("关于", systemImage: "info.circle")
                    }
                }
            }
            .listStyle(.insetGrouped)
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
        List {
            Section {
                HStack {
                    Label(
                        "密钥状态",
                        systemImage: vaultStore.isKeyLoaded ? "lock.open.fill" : "lock.fill"
                    )
                    Spacer()
                    Text(vaultStore.isKeyLoaded ? "已加载" : "未加载")
                        .foregroundStyle(.secondary)
                }
            }

            if vaultStore.isKeyLoaded {
                Section {
                    Button {
                        exportKeyFile()
                    } label: {
                        Label("导出密钥", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showUnloadConfirmation = true
                    } label: {
                        Label("卸载本机密钥", systemImage: "lock.slash")
                    }
                }
            } else {
                Section {
                    Button {
                        Task {
                            do { try await vaultStore.createKey() }
                            catch { vaultStore.lastError = "创建密钥失败：\(error.localizedDescription)" }
                        }
                    } label: {
                        Label("创建密钥", systemImage: "key.fill")
                    }
                    Button {
                        showKeyImporter = true
                    } label: {
                        Label("导入密钥文件", systemImage: "square.and.arrow.down")
                    }
                } footer: {
                    Text("密钥文件只会在本机读取，不会上传。")
                }
            }

            Section {
                Button(role: .destructive) {
                    showResetFirstConfirmation = true
                } label: {
                    Label("重置密钥", systemImage: "trash")
                }
            } footer: {
                Text("重置密钥将删除所有加密笔记，明文笔记会保留。")
            }
        }
        .listStyle(.insetGrouped)
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
        List {
            Section {
                Toggle("进入后台时隐藏内容", isOn: $settings.hideContentOnBackground)
                Toggle("重新打开 App 时自动卸载密钥", isOn: $settings.autoUnloadKeyOnForeground)
            } footer: {
                Text("自动卸载密钥不会删除笔记，只会让加密笔记回到乱码状态。")
            }
        }
        .listStyle(.insetGrouped)
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
        List {
            Section {
                Button {
                    isPresented = false
                    showTrash = true
                } label: {
                    HStack {
                        Label("查看回收站", systemImage: "trash")
                        Spacer()
                        if vaultStore.trashCount > 0 {
                            Text("\(vaultStore.trashCount)")
                                .foregroundColor(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.primary)
            }

            Section {
                Button {
                    Task { await vaultStore.purgeExpiredTrash() }
                } label: {
                    Label("清理 30 天前删除的笔记", systemImage: "clock.arrow.circlepath")
                }
                Button(role: .destructive) {
                    showEmptyConfirmation = true
                } label: {
                    Label("清空回收站", systemImage: "trash.slash")
                }
            } footer: {
                Text("回收站笔记将在删除 30 天后自动永久删除。")
            }
        }
        .listStyle(.insetGrouped)
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
        List {
            Section {
                HStack {
                    Text("应用名称")
                    Spacer()
                    Text("别看我").foregroundColor(.secondary)
                }
                HStack {
                    Text("当前版本")
                    Spacer()
                    Text("v0.2").foregroundColor(.secondary)
                }
            }

            Section {
                Text("iCloud 同步：笔记文件保存在 iCloud Drive 中，可在多设备间同步。")
                    .font(DS.caption())
                    .foregroundColor(.secondary)
                Text("明文笔记不会加密，适合普通内容；敏感内容建议使用加密笔记。")
                    .font(DS.caption())
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}
