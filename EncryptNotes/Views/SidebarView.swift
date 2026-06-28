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
        VStack(spacing: 0) {
            header
            Divider().padding(.vertical, DS.s2)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.s5) {
                    keyCard
                    navSection
                    tagSection
                    trashEntry
                }
                .padding(.horizontal, DS.cardPadding)
                .padding(.vertical, DS.s3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.bg.ignoresSafeArea())
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
        HStack(spacing: DS.s3) {
            Text("别看我")
                .font(DS.page())
                .foregroundColor(DS.textEmphasize)

            Spacer()

            syncStatusIcon

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isPresented = false
                    showSettings = true
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(DS.textSecondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, DS.cardPadding)
        .padding(.top, DS.s2)
    }

    @ViewBuilder
    private var syncStatusIcon: some View {
        switch syncStore.status {
        case .syncing:
            ProgressView()
                .controlSize(.small)
        case .saved:
            Image(systemName: syncStore.isNetworkAvailable ? "icloud" : "icloud.slash")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(DS.textSubtle)
        case .failed:
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(DS.destructive)
        }
    }

    @ViewBuilder
    private var keyCard: some View {
        VStack(alignment: .leading, spacing: DS.s3) {
            if vaultStore.isKeyLoaded {
                HStack {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.primaryDeep)
                    Text("密钥已加载")
                        .font(DS.title())
                        .foregroundColor(DS.textEmphasize)
                    Spacer()
                }

                VStack(spacing: 0) {
                    sidebarButton(icon: "square.and.arrow.up", title: "导出密钥", destructive: false) {
                        exportKeyFile()
                    }
                    Divider().padding(.leading, 32)
                    sidebarButton(icon: "lock.slash", title: "卸载本机密钥", destructive: false) {
                        showUnloadConfirmation = true
                    }
                    Divider().padding(.leading, 32)
                    sidebarButton(icon: "trash", title: "重置密钥", destructive: true) {
                        showResetFirstConfirmation = true
                    }
                }
                .background(DS.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                        .stroke(DS.line, lineWidth: 0.5)
                )
            } else {
                HStack {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.pro)
                    Text("未加载密钥")
                        .font(DS.title())
                        .foregroundColor(DS.textEmphasize)
                    Spacer()
                }

                Button {
                    Task {
                        do {
                            try await vaultStore.createKey()
                        } catch {
                            vaultStore.lastError = "创建密钥失败：\(error.localizedDescription)"
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "key.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("创建密钥")
                            .font(DS.body())
                        Spacer()
                    }
                    .foregroundColor(DS.onPrimary)
                    .padding(.horizontal, DS.s3)
                    .padding(.vertical, DS.s3)
                    .background(DS.primary)
                    .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
                }
                .buttonStyle(.plain)

                VStack(spacing: 0) {
                    sidebarButton(icon: "square.and.arrow.down", title: "导入密钥文件", destructive: false) {
                        showKeyImporter = true
                    }
                    Divider().padding(.leading, 32)
                    sidebarButton(icon: "trash", title: "重置密钥", destructive: true) {
                        showResetFirstConfirmation = true
                    }
                }
                .background(DS.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                        .stroke(DS.line, lineWidth: 0.5)
                )

                Text("密钥文件只会在本机读取，不会上传。")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
            }
        }
    }

    private var navSection: some View {
        VStack(alignment: .leading, spacing: DS.s1) {
            Button {
                vaultStore.selectedTag = nil
                withAnimation(.easeInOut(duration: 0.3)) {
                    isPresented = false
                }
            } label: {
                HStack(spacing: DS.s3) {
                    Image(systemName: "note.text")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(DS.textSecondary)
                        .frame(width: 24)
                    Text("全部笔记")
                        .font(DS.body())
                        .foregroundColor(DS.textBody)
                    Spacer()
                    Text("\(vaultStore.readableNoteCount)")
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)
                }
                .padding(.horizontal, DS.s3)
                .padding(.vertical, DS.s2)
                .background(vaultStore.selectedTag == nil ? DS.primaryContainer : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var tagSection: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            Text("标签")
                .font(DS.caption())
                .foregroundColor(DS.textSecondary)
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
                        Button {
                            vaultStore.selectedTag = vaultStore.selectedTag == tagCount.tag ? nil : tagCount.tag
                            if vaultStore.selectedTag != nil {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isPresented = false
                                }
                            }
                        } label: {
                            HStack(spacing: DS.s3) {
                                Image(systemName: "number")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(DS.primary)
                                    .frame(width: 24)
                                Text(tagCount.tag)
                                    .font(DS.body())
                                    .foregroundColor(DS.textBody)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(tagCount.count)")
                                    .font(DS.caption())
                                    .foregroundColor(DS.textSubtle)
                            }
                            .padding(.horizontal, DS.s3)
                            .padding(.vertical, DS.s2)
                            .background(vaultStore.selectedTag == tagCount.tag ? DS.primaryContainer : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var trashEntry: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                isPresented = false
                showTrash = true
            }
        } label: {
            HStack(spacing: DS.s3) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(DS.textSecondary)
                    .frame(width: 24)
                Text("回收站")
                    .font(DS.body())
                    .foregroundColor(DS.textBody)
                Spacer()
                if vaultStore.trashCount > 0 {
                    Text("\(vaultStore.trashCount)")
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)
                }
            }
            .padding(.horizontal, DS.s3)
            .padding(.vertical, DS.s2)
        }
        .buttonStyle(.plain)
    }

    private func sidebarButton(icon: String, title: String, destructive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.s3) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(destructive ? DS.destructive : DS.textSecondary)
                    .frame(width: 24)
                Text(title)
                    .font(DS.body())
                    .foregroundColor(destructive ? DS.destructive : DS.textBody)
                Spacer()
            }
            .padding(.horizontal, DS.s3)
            .padding(.vertical, DS.s3)
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
