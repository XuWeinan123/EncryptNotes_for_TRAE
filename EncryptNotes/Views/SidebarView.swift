import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Binding var isPresented: Bool
    @Binding var showSettings: Bool
    @Binding var showTrash: Bool

    @StateObject private var vaultStore = VaultStore.shared
    @StateObject private var syncStore = SyncStatusStore.shared

    @State private var showKeyImporter = false
    @State private var exportedKeyURL: URL?
    @State private var showShareSheet = false
    @State private var showUnloadConfirmation = false
    @State private var showResetFirstConfirmation = false
    @State private var showResetSecondConfirmation = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.s6) {
                header
                keyCard
                navSection
                tagSection
                trashEntry
            }
            .padding(.horizontal, DS.cardPadding)
            .padding(.top, DS.s6)
            .padding(.bottom, DS.s8)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.surfaceRaised.ignoresSafeArea())
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
        .alert("保存密钥文件", isPresented: $vaultStore.needsKeyExport) {
            Button("立即保存") { exportKeyFile() }
            Button("稍后", role: .cancel) { vaultStore.needsKeyExport = false }
        } message: {
            Text("请保存你的密钥文件（.bkwkey）。没有密钥文件，换设备或重装应用后将无法解密笔记。")
        }
        .alert("卸载本机密钥", isPresented: $showUnloadConfirmation) {
            Button("取消", role: .cancel) {}
            Button("继续卸载", role: .destructive) {
                Task {
                    do {
                        try await vaultStore.unloadKey()
                    } catch {
                        vaultStore.lastError = "卸载密钥失败：\(error.localizedDescription)"
                    }
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
                    do {
                        try await vaultStore.resetKey()
                    } catch {
                        vaultStore.lastError = "重置密钥失败：\(error.localizedDescription)"
                    }
                }
            }
        } message: {
            Text("确定要删除所有加密笔记并生成新密钥吗？此操作不可撤销。")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DS.s3) {
            Text("别看我")
                .font(DS.page())
                .foregroundColor(DS.textEmphasize)

            Spacer()

            syncStatusIcon

            Button {
                isPresented = false
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .regular))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(DS.textSecondary)
            .accessibilityLabel("设置")
        }
    }

    @ViewBuilder
    private var syncStatusIcon: some View {
        switch syncStore.status {
        case .syncing:
            ProgressView()
                .controlSize(.small)
                .frame(width: 32, height: 32)
                .accessibilityLabel("正在同步")
        case .saved:
            Image(systemName: syncStore.isNetworkAvailable ? "icloud" : "icloud.slash")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(DS.textSecondary)
                .frame(width: 32, height: 32)
                .accessibilityLabel(syncStore.isNetworkAvailable ? "iCloud 已同步" : "iCloud 离线")
        case .failed:
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(DS.destructive)
                .frame(width: 32, height: 32)
                .accessibilityLabel("iCloud 同步失败")
        }
    }

    @ViewBuilder
    private var keyCard: some View {
        VStack(alignment: .leading, spacing: DS.s3) {
            HStack(spacing: DS.s2) {
                Image(systemName: vaultStore.isKeyLoaded ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(vaultStore.isKeyLoaded ? DS.primaryDeep : DS.pro)

                Text(vaultStore.isKeyLoaded ? "密钥已加载" : "未加载密钥")
                    .font(DS.title())
                    .foregroundColor(DS.textEmphasize)

                Spacer()
            }

            if vaultStore.isKeyLoaded {
                VStack(spacing: 0) {
                    sidebarActionRow(icon: "square.and.arrow.up", title: "导出密钥") {
                        exportKeyFile()
                    }
                    Divider().padding(.leading, 32)
                    sidebarActionRow(icon: "lock.slash", title: "卸载本机密钥") {
                        showUnloadConfirmation = true
                    }
                    Divider().padding(.leading, 32)
                    sidebarActionRow(icon: "trash", title: "重置密钥", destructive: true) {
                        showResetFirstConfirmation = true
                    }
                }
            } else {
                Button {
                    Task {
                        do {
                            try await vaultStore.createKey()
                        } catch {
                            vaultStore.lastError = "创建密钥失败：\(error.localizedDescription)"
                        }
                    }
                } label: {
                    Label("创建密钥", systemImage: "key.fill")
                        .font(DS.body())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundColor(DS.onPrimary)
                .padding(.horizontal, DS.s3)
                .frame(height: 36)
                .background(DS.primary)
                .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))

                VStack(spacing: 0) {
                    sidebarActionRow(icon: "square.and.arrow.down", title: "导入密钥文件") {
                        showKeyImporter = true
                    }
                    Divider().padding(.leading, 32)
                    sidebarActionRow(icon: "trash", title: "重置密钥", destructive: true) {
                        showResetFirstConfirmation = true
                    }
                }

                Text("密钥文件只会在本机读取，不会上传。")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
            }
        }
        .padding(DS.s3)
        .dsCardSurface(cornerRadius: DS.rMd, shadow: false)
    }

    private var navSection: some View {
        VStack(alignment: .leading, spacing: DS.s1) {
            sidebarNavRow(
                icon: "square.grid.2x2.fill",
                title: "全部笔记",
                count: vaultStore.readableNoteCount,
                isSelected: vaultStore.selectedTag == nil
            ) {
                vaultStore.selectedTag = nil
                isPresented = false
            }
        }
    }

    @ViewBuilder
    private var tagSection: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            Text("标签")
                .font(DS.caption())
                .foregroundColor(DS.sidebarSectionTitle)
                .padding(.horizontal, DS.s3)

            if vaultStore.allTags.isEmpty {
                Text("暂无标签")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
                    .padding(.horizontal, DS.s3)
                    .padding(.vertical, DS.s1)
            } else {
                VStack(spacing: 2) {
                    ForEach(vaultStore.allTags) { tagCount in
                        sidebarNavRow(
                            icon: "number",
                            title: tagCount.tag,
                            count: tagCount.count,
                            isSelected: vaultStore.selectedTag == tagCount.tag
                        ) {
                            vaultStore.selectedTag = vaultStore.selectedTag == tagCount.tag ? nil : tagCount.tag
                            if vaultStore.selectedTag != nil {
                                isPresented = false
                            }
                        }
                    }
                }
            }
        }
    }

    private var trashEntry: some View {
        sidebarNavRow(
            icon: "trash",
            title: "回收站",
            count: vaultStore.trashCount > 0 ? vaultStore.trashCount : nil,
            isSelected: false
        ) {
            isPresented = false
            showTrash = true
        }
    }

    private func sidebarNavRow(
        icon: String,
        title: String,
        count: Int? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DS.s3) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)

                Text(title)
                    .font(DS.body())
                    .lineLimit(1)

                Spacer()

                if let count {
                    Text("\(count)")
                        .font(DS.caption())
                        .foregroundColor(isSelected ? DS.onPrimary.opacity(0.78) : DS.sidebarMetric)
                }
            }
            .foregroundColor(isSelected ? DS.onPrimary : DS.textBody)
            .padding(.horizontal, DS.s3)
            .frame(height: DS.sidebarRowHeight)
            .background(isSelected ? DS.primary : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DS.sidebarRowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func sidebarActionRow(
        icon: String,
        title: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DS.s2) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 22)

                Text(title)
                    .font(DS.body())

                Spacer()
            }
            .foregroundColor(destructive ? DS.destructive : DS.textBody)
            .padding(.vertical, DS.s2)
        }
        .buttonStyle(.plain)
    }

    private func handleKeyImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    _ = try await vaultStore.importKeyFile(from: url)
                } catch {
                    vaultStore.lastError = "导入密钥失败：\(error.localizedDescription)"
                }
            }
        case .failure:
            break
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
}
