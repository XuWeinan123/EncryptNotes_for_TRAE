import SwiftUI
import UniformTypeIdentifiers

/// 侧边栏：用户信息、统计、快捷入口、标签列表、回收站入口。
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
            VStack(alignment: .leading, spacing: DS.s4) {
                header
                contributionSection
                quickActions
                keyActions
                pinnedSection
                tagSection
                trashEntry
            }
            .padding(.horizontal, DS.s3)
            .padding(.top, DS.s3)
            .padding(.bottom, DS.s8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        HStack(spacing: DS.s2) {
            Text("别看我")
                .font(DS.page())
                .foregroundColor(DS.textEmphasize)

            Text("PRO")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(DS.onPrimary)
                .padding(.horizontal, DS.s1)
                .padding(.vertical, 2)
                .background(DS.textBody)
                .clipShape(RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))

            Circle()
                .fill(DS.destructive)
                .frame(width: 5, height: 5)

            Spacer()

            headerButton(systemName: "bell") {}

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isPresented = false
                    showSettings = true
                }
            } label: {
                sidebarIcon("gearshape")
            }
            .buttonStyle(.plain)
        }
        .frame(height: 36)
    }

    private var contributionSection: some View {
        VStack(alignment: .leading, spacing: DS.s4) {
            HStack(alignment: .top) {
                sidebarMetric(value: "\(vaultStore.readableNoteCount)", title: "笔记")
                Spacer()
                sidebarMetric(value: "\(vaultStore.allTags.count)", title: "标签")
                Spacer()
                sidebarMetric(value: activeDaysText, title: "天")
            }

            ContributionGrid(seed: vaultStore.readableNoteCount + vaultStore.lockedNoteCount + vaultStore.allTags.count)
        }
        .padding(.horizontal, DS.s3)
    }

    private var activeDaysText: String {
        let dates = Set(vaultStore.readableNotes.map { Calendar.current.startOfDay(for: $0.updatedAt) })
        return "\(max(dates.count, vaultStore.readableNotes.isEmpty ? 0 : 1))"
    }

    @ViewBuilder
    private var quickActions: some View {
        VStack(spacing: 0) {
            SidebarRow(
                title: "全部笔记",
                systemImage: "square.grid.2x2.fill",
                isSelected: vaultStore.selectedTag == nil
            ) {
                vaultStore.selectedTag = nil
                withAnimation(.easeInOut(duration: 0.3)) { isPresented = false }
            }

            SidebarRow(title: "微信输入", systemImage: "message.fill", isEnabled: false) {}
            SidebarRow(title: "每日回顾", systemImage: "sparkles", isEnabled: false) {}
            SidebarRow(title: "AI 洞察", systemImage: "circle.hexagongrid", isEnabled: false) {}
        }
    }

    @ViewBuilder
    private var keyActions: some View {
        VStack(spacing: 0) {
            if vaultStore.isKeyLoaded {
                SidebarRow(title: "导出密钥", systemImage: "square.and.arrow.up") {
                    exportKeyFile()
                }
                SidebarRow(title: "卸载本机密钥", systemImage: "lock.slash") {
                    showUnloadConfirmation = true
                }
            } else {
                SidebarRow(title: "创建密钥", systemImage: "key.fill") {
                    Task {
                        do { try await vaultStore.createKey() }
                        catch { vaultStore.lastError = "创建密钥失败：\(error.localizedDescription)" }
                    }
                }
                SidebarRow(title: "导入密钥文件", systemImage: "square.and.arrow.down") {
                    showKeyImporter = true
                }
            }
            SidebarRow(title: "重置密钥", systemImage: "trash", role: .destructive) {
                showResetFirstConfirmation = true
            }
        }
    }

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            sectionTitle("置顶标签")
            SidebarRow(title: "新人指南", leadingText: "📖", isEnabled: false) {}
        }
    }

    @ViewBuilder
    private var tagSection: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            sectionTitle("全部标签")

            if vaultStore.allTags.isEmpty {
                SidebarRow(title: "暂无标签", systemImage: "number", isEnabled: false) {}
            } else {
                ForEach(vaultStore.allTags) { tagCount in
                    SidebarRow(
                        title: tagCount.tag,
                        systemImage: "number",
                        accessory: "\(tagCount.count)",
                        isSelected: vaultStore.selectedTag == tagCount.tag
                    ) {
                    vaultStore.selectedTag = vaultStore.selectedTag == tagCount.tag ? nil : tagCount.tag
                    withAnimation(.easeInOut(duration: 0.3)) { isPresented = false }
                    }
                }
            }
        }
    }

    private var trashEntry: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            SidebarRow(
                title: "回收站",
                systemImage: "trash",
                accessory: vaultStore.trashCount > 0 ? "\(vaultStore.trashCount)" : nil
            ) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isPresented = false
                    showTrash = true
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(DS.caption())
            .foregroundColor(DS.sidebarSectionTitle)
            .frame(height: 12, alignment: .center)
            .padding(.horizontal, DS.s3)
    }

    private func sidebarMetric(value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(DS.sidebarMetric)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(title)
                .font(DS.caption())
                .foregroundColor(DS.sidebarMetric)
        }
        .frame(width: 56, alignment: .leading)
    }

    private func headerButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            sidebarIcon(systemName)
        }
        .buttonStyle(.plain)
    }

    private func sidebarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .regular))
            .foregroundColor(DS.textSubtle)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
    }

    private struct SidebarRow: View {
        let title: String
        var systemImage: String?
        var leadingText: String?
        var accessory: String?
        var isSelected = false
        var isEnabled = true
        var role: ButtonRole?
        let action: () -> Void

        var body: some View {
            Button(role: role) {
                if isEnabled { action() }
            } label: {
                HStack(spacing: DS.s2) {
                    leadingView

                    Text(title)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(titleColor)
                        .lineLimit(1)

                    Spacer(minLength: DS.s2)

                    if let accessory {
                        Text(accessory)
                            .font(DS.caption())
                            .foregroundColor(isSelected ? DS.onPrimary.opacity(0.8) : DS.textSubtle)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .frame(height: DS.sidebarRowHeight)
            .padding(.horizontal, DS.s3)
            .background(isSelected ? DS.primary : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DS.sidebarRowRadius, style: .continuous))
            .opacity(isEnabled ? 1.0 : 0.72)
        }

        @ViewBuilder
        private var leadingView: some View {
            if let leadingText {
                Text(leadingText)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 16, height: 16)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(iconColor)
                    .frame(width: 16, height: 16)
            }
        }

        private var titleColor: Color {
            if role == .destructive { return DS.destructive }
            return isSelected ? DS.onPrimary : DS.textEmphasize
        }

        private var iconColor: Color {
            if role == .destructive { return DS.destructive }
            return isSelected ? DS.onPrimary : DS.textEmphasize
        }
    }

    private struct ContributionGrid: View {
        let seed: Int
        private let columns = Array(repeating: GridItem(.fixed(16), spacing: 8), count: 10)

        var body: some View {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0..<60, id: \.self) { index in
                    RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                        .fill(color(for: index))
                        .frame(width: 16, height: 16)
                }
            }
            .frame(width: 232, alignment: .leading)
        }

        private func color(for index: Int) -> Color {
            let value = (index * 7 + seed * 3) % 11
            switch value {
            case 0...4: return DS.contribution0
            case 5...6: return DS.contribution1
            case 7...8: return DS.contribution2
            default: return DS.contribution3
            }
        }
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
