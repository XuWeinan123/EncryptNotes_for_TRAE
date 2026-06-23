import SwiftUI
import UniformTypeIdentifiers

/// 侧边栏：应用名称 + 设置入口、密钥卡片、标签列表、回收站入口。
struct SidebarView: View {
    @Binding var isPresented: Bool
    @Binding var showSettings: Bool
    @Binding var showTrash: Bool

    @StateObject private var vaultStore = VaultStore.shared

    @State private var showKeyImporter = false
    @State private var showKeyExportGuide = false
    @State private var showUnloadConfirmation = false
    @State private var showResetFirstConfirmation = false
    @State private var showResetSecondConfirmation = false
    @State private var exportedKeyURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.s6) {
                header
                keyCard
                tagSection
                trashEntry
            }
            .padding(.horizontal, DS.cardPadding)
            .padding(.vertical, DS.s4)
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
        .alert("保存密钥文件", isPresented: $showKeyExportGuide) {
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
        HStack {
            Text("别看我")
                .font(DS.page())
                .foregroundColor(DS.textEmphasize)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isPresented = false
                    showSettings = true
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(DS.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var keyCard: some View {
        VStack(alignment: .leading, spacing: DS.s3) {
            if vaultStore.isKeyLoaded {
                HStack {
                    Text("密钥已加载")
                        .font(DS.title())
                        .foregroundColor(DS.textEmphasize)
                    Spacer()
                    SWStatusBadge("可查看", systemImage: "lock.open.fill", style: .success)
                }
                Text("加密笔记已在本机解密显示。")
                    .font(DS.caption())
                    .foregroundColor(DS.textSecondary)

                VStack(spacing: DS.s2) {
                    Button {
                        exportKeyFile()
                    } label: {
                        Label("导出密钥", systemImage: "square.and.arrow.up")
                            .font(DS.body())
                            .foregroundColor(DS.textBody)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button {
                        showUnloadConfirmation = true
                    } label: {
                        Label("卸载本机密钥", systemImage: "lock.slash")
                            .font(DS.body())
                            .foregroundColor(DS.textBody)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button {
                        showResetFirstConfirmation = true
                    } label: {
                        Label("重置密钥", systemImage: "trash")
                            .font(DS.body())
                            .foregroundColor(DS.destructive)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                HStack {
                    Text("未加载密钥")
                        .font(DS.title())
                        .foregroundColor(DS.textEmphasize)
                    Spacer()
                    SWStatusBadge("待导入", systemImage: "lock.fill", style: .warning)
                }
                Text("加密笔记将以乱码显示。")
                    .font(DS.caption())
                    .foregroundColor(DS.textSecondary)

                VStack(spacing: DS.s2) {
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
                            .foregroundColor(DS.onPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(DS.primary)
                            .clipShape(RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showKeyImporter = true
                    } label: {
                        Label("导入密钥文件", systemImage: "square.and.arrow.down")
                            .font(DS.body())
                            .foregroundColor(DS.textBody)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button {
                        showResetFirstConfirmation = true
                    } label: {
                        Label("重置密钥", systemImage: "trash")
                            .font(DS.body())
                            .foregroundColor(DS.destructive)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text("密钥文件只会在本机读取，不会上传。")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
                Text("重置密钥会删除所有加密笔记，明文笔记会保留。")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
            }
            HStack(spacing: DS.s2) {
                SWStatusBadge("可读 \(vaultStore.readableNoteCount)", systemImage: "doc.text", style: .neutral)
                if vaultStore.lockedNoteCount > 0 {
                    SWStatusBadge("待解锁 \(vaultStore.lockedNoteCount)", systemImage: "exclamationmark.lock", style: .warning)
                }
            }
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCardSurface()
    }

    @ViewBuilder
    private var tagSection: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            Text("标签")
                .font(DS.caption())
                .foregroundColor(DS.textSecondary)

            Button {
                vaultStore.selectedTag = nil
            } label: {
                HStack {
                    Text("全部")
                        .font(DS.body())
                        .foregroundColor(vaultStore.selectedTag == nil ? DS.primaryDeep : DS.textBody)
                    Spacer()
                    Text("\(vaultStore.readableNotes.count)")
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)
                }
                .padding(.vertical, DS.s1)
                .padding(.horizontal, DS.s2)
                .background(vaultStore.selectedTag == nil ? DS.primaryContainer : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))
            }
            .buttonStyle(.plain)

            ForEach(vaultStore.allTags) { tagCount in
                Button {
                    vaultStore.selectedTag = vaultStore.selectedTag == tagCount.tag ? nil : tagCount.tag
                } label: {
                    HStack {
                        Text(tagCount.tag)
                            .font(DS.body())
                            .foregroundColor(vaultStore.selectedTag == tagCount.tag ? DS.primaryDeep : DS.textBody)
                        Spacer()
                        Text("\(tagCount.count)")
                            .font(DS.caption())
                            .foregroundColor(DS.textSubtle)
                    }
                    .padding(.vertical, DS.s1)
                    .padding(.horizontal, DS.s2)
                    .background(vaultStore.selectedTag == tagCount.tag ? DS.primaryContainer : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if vaultStore.allTags.isEmpty {
                Text("暂无标签")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
                    .padding(.vertical, DS.s1)
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
            HStack {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(DS.textSecondary)
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
