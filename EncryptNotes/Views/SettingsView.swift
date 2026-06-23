import SwiftUI
import UniformTypeIdentifiers

/// 设置页：笔记 / 密钥与加密 / 隐私保护 / 数据 / 关于。
struct SettingsView: View {
    @Binding var isPresented: Bool
    @Binding var showTrash: Bool
    @StateObject private var vaultStore = VaultStore.shared
    @StateObject private var settings = SettingsStore.shared

    @State private var showKeyImporter = false
    @State private var showResetFirstConfirmation = false
    @State private var showResetSecondConfirmation = false
    @State private var showUnloadConfirmation = false
    @State private var exportedKeyURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                noteSection
                keySection
                privacySection
                dataSection
                aboutSection
            }
            .padding(DS.cardPadding)
            .frame(maxWidth: DS.contentMax)
            .frame(maxWidth: .infinity)
            .font(DS.bodyLg())
            .foregroundColor(DS.textBody)
            .dsCanvasBackground()
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .dsLiquidGlassToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        withAnimation(.easeInOut(duration: 0.3)) { isPresented = false }
                    }
                    .dsToolbarButtonStyle()
                }
            }
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
    }

    // MARK: - 1. 笔记

    private var noteSection: some View {
        settingsCard(title: "笔记", systemImage: "note.text") {
            settingValueRow("默认新建模式", value: vaultStore.isKeyLoaded && settings.preferredNoteMode == .encrypted ? "加密" : "明文")
            helperText("新建笔记会记住你上一次选择的模式。未加载密钥时，将默认创建明文笔记。")
            helperText("输入 #标签 并用空格、换行或正文结尾结束，即可创建标签。")
        }
    }

    // MARK: - 2. 密钥与加密

    private var keySection: some View {
        settingsCard(title: "密钥与加密", systemImage: "lock") {
            HStack {
                settingValueRow("密钥状态", value: vaultStore.isKeyLoaded ? "已加载" : "未加载")
                SWStatusBadge(
                    vaultStore.isKeyLoaded ? "可查看" : "待导入",
                    systemImage: vaultStore.isKeyLoaded ? "lock.open.fill" : "lock.fill",
                    style: vaultStore.isKeyLoaded ? .success : .warning
                )
            }

            if vaultStore.isKeyLoaded {
                Button {
                    exportKeyFile()
                } label: {
                    Label("导出密钥", systemImage: "square.and.arrow.up")
                }
                Button {
                    showUnloadConfirmation = true
                } label: {
                    Label("卸载本机密钥", systemImage: "lock.slash")
                }
            } else {
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
            }

            Button(role: .destructive) {
                showResetFirstConfirmation = true
            } label: {
                Label("重置密钥", systemImage: "trash")
                    .foregroundColor(DS.destructive)
            }

            helperText("明文笔记会直接保存到 iCloud 文件中。加密笔记会先在本机加密，再保存到 iCloud。")
            helperText("密钥文件只会在本机读取，不会上传。")
        }
    }

    // MARK: - 3. 隐私保护

    private var privacySection: some View {
        settingsCard(title: "隐私保护", systemImage: "hand.raised") {
            Toggle(isOn: $settings.hideContentOnBackground) {
                Text("进入后台时隐藏内容")
            }
            Toggle(isOn: $settings.autoUnloadKeyOnForeground) {
                Text("重新打开 App 时自动卸载密钥")
            }
            Text("自动卸载密钥不会删除笔记，只会让加密笔记回到乱码状态。")
                .font(DS.caption())
                .foregroundColor(DS.textSecondary)
        }
    }

    // MARK: - 4. 数据

    private var dataSection: some View {
        settingsCard(title: "数据", systemImage: "tray") {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isPresented = false
                    showTrash = true
                }
            } label: {
                HStack {
                    Text("回收站")
                    Spacer()
                    if vaultStore.trashCount > 0 {
                        Text("\(vaultStore.trashCount)")
                            .foregroundColor(DS.textSecondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.textSubtle)
                }
            }
            Button {
                Task { await vaultStore.purgeExpiredTrash() }
            } label: {
                Text("清理 30 天前删除的笔记")
            }
        }
    }

    // MARK: - 5. 关于

    private var aboutSection: some View {
        settingsCard(title: "关于", systemImage: "info.circle") {
            settingValueRow("应用名称", value: "别看我")
            settingValueRow("当前版本", value: "v0.2")
            helperText("iCloud 同步：笔记文件保存在 iCloud Drive 中，可在多设备间同步。")
            helperText("明文笔记不会加密，适合普通内容；敏感内容建议使用加密笔记。")
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.s3) {
            Label(title, systemImage: systemImage)
                .font(DS.title())
                .foregroundColor(DS.textEmphasize)
            content()
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCardSurface(cornerRadius: DS.rMd)
        .padding(.bottom, DS.s3)
    }

    private func settingValueRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(DS.textSecondary)
        }
    }

    private func helperText(_ text: String) -> some View {
        Text(text)
            .font(DS.caption())
            .foregroundColor(DS.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Helpers

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

/// 系统分享 sheet 包装。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
