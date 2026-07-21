import SwiftUI

struct SidebarView: View {
    @Binding var isPresented: Bool
    @Binding var showSettings: Bool
    @Binding var showTrash: Bool

    @StateObject private var vaultStore = VaultStore.shared
    @StateObject private var syncStore = SyncStatusStore.shared

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
        .alert("保存密钥", isPresented: $vaultStore.needsKeyExport) {
            Button("打开密钥设置") { openSettings() }
            Button("稍后", role: .cancel) { vaultStore.needsKeyExport = false }
        } message: {
            Text("请前往密钥设置导出并妥善保存密钥。没有密钥，换设备或重装应用后将无法解密笔记。")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DS.s3) {
            Text("Seal Note")
                .font(DS.page())
                .foregroundColor(DS.textEmphasize)

            Spacer()

            syncStatusIcon

            Button {
                openSettings()
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
        case .pendingDownloads(let count):
            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(DS.pro)
                .frame(width: 32, height: 32)
                .accessibilityLabel("正在下载 \(count) 篇笔记")
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

            Button {
                openSettings()
            } label: {
                Label("打开密钥设置", systemImage: "key.fill")
                    .font(DS.body())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundColor(DS.onPrimary)
            .padding(.horizontal, DS.s3)
            .frame(height: 36)
            .background(DS.primary)
            .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))

            Text(keyCardSubtitle)
                .font(DS.caption())
                .foregroundColor(DS.textSubtle)
        }
        .padding(DS.s3)
        .dsCardSurface(cornerRadius: DS.rMd, shadow: false)
    }

    private var keyCardSubtitle: String {
        if vaultStore.isKeyLoaded {
            return "导出、移除或处理加密笔记请前往设置。"
        }
        if vaultStore.encryptedEntryCount > 0 {
            return "已有加密笔记，请前往设置加载原密钥。"
        }
        return "密钥只会在本机读取，不会上传。"
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

    private func openSettings() {
        isPresented = false
        showSettings = true
    }
}
