import Foundation
import SwiftUI

struct TrashView: View {
    @ObservedObject private var vaultStore = VaultStore.shared
    @State private var showingEmptyTrashConfirmation = false
    @State private var searchText = ""
    @State private var isSearchBarVisible = false
    @State private var actionErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if isSearchBarVisible {
                MacListSearchBar(
                    placeholder: "搜索回收站…",
                    text: $searchText,
                    onClose: { hideSearchBar() }
                )
            }

            List {
                listSummary
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(DS.bg)

                if filteredTrashNotes.isEmpty {
                    emptyRow
                        .listRowInsets(EdgeInsets(top: DS.s3, leading: DS.s3, bottom: DS.s3, trailing: DS.s3))
                        .listRowSeparator(.hidden)
                        .listRowBackground(DS.bg)
                } else {
                    ForEach(filteredTrashNotes) { trashNote in
                        trashRow(for: trashNote)
                            .contextMenu {
                                Button("恢复") {
                                    restore(trashNote)
                                }
                                Button("永久删除", role: .destructive) {
                                    permanentlyDelete(trashNote)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: DS.s1, leading: DS.s3, bottom: DS.s1, trailing: DS.s3))
                            .listRowSeparator(.hidden)
                            .listRowBackground(DS.bg)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.bg)
        }
        .background(DS.bg)
        .dsLiquidGlassToolbar()
        .navigationTitle("回收站")
        .toolbar { trashToolbar }
        .background(MacListSearchToolbarAppearance(isActive: isSearchBarVisible))
        .alert("确认清空回收站？", isPresented: $showingEmptyTrashConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                emptyTrash()
            }
        } message: {
            Text("回收站中的所有笔记将被永久删除，无法恢复。")
        }
        .alert("操作失败", isPresented: actionErrorBinding) {
            Button("好") {
                actionErrorMessage = nil
            }
        } message: {
            Text(actionErrorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var trashToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                toggleSearchBar()
            } label: {
                Label("搜索", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .help("搜索")
            .keyboardShortcut("f", modifiers: .command)

            Button(role: .destructive) {
                showingEmptyTrashConfirmation = true
            } label: {
                Label("清空", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .disabled(vaultStore.trashNotes.isEmpty)
            .help(vaultStore.trashNotes.isEmpty ? "回收站为空" : "永久删除回收站中的所有笔记")
        }
    }

    private func toggleSearchBar() {
        if isSearchBarVisible {
            hideSearchBar()
        } else {
            isSearchBarVisible = true
        }
    }

    private func hideSearchBar() {
        isSearchBarVisible = false
        searchText = ""
    }

    private var listSummary: some View {
        HStack(spacing: DS.s2) {
            Spacer(minLength: 0)
            Text("回收站 \(filteredTrashNotes.count) 条笔记")
                .font(DS.caption())
                .foregroundColor(DS.textSubtle)
            Text(vaultStore.trashNotes.isEmpty ? "没有已删除笔记" : "删除的笔记会保留 30 天")
                .font(DS.caption())
                .foregroundColor(DS.textSubtle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.s3)
        .padding(.top, DS.s3)
        .padding(.bottom, DS.s2)
    }

    private var filteredTrashNotes: [TrashNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return vaultStore.trashNotes }
        return vaultStore.trashNotes.filter { trashNote in
            trashTitle(for: trashNote).localizedCaseInsensitiveContains(query)
                || trashNote.body?.localizedCaseInsensitiveContains(query) == true
        }
    }

    private var emptyRow: some View {
        SWEmptyState(
            title: vaultStore.trashNotes.isEmpty ? "回收站为空" : "没有匹配的笔记",
            message: vaultStore.trashNotes.isEmpty ? "删除的笔记会在这里保留 30 天" : "换个关键词试试，或清空搜索内容。",
            systemImage: "trash"
        )
    }

    @ViewBuilder
    private func trashRow(for trashNote: TrashNote) -> some View {
        TrashListRow(
            title: trashTitle(for: trashNote),
            subtitle: "删除于 \(timeString(from: trashNote.deletedAt))"
        ) {
            HStack(spacing: DS.s4) {
                HStack(spacing: DS.s2) {
                    if trashNote.isEncrypted {
                        SWStatusBadge("加密", systemImage: "lock.fill", style: .neutral)
                    }
                    SWStatusBadge("\(trashNote.remainingDays) 天", systemImage: "clock", style: .warning)
                }

                HStack(spacing: DS.s1) {
                    Button {
                        restore(trashNote)
                    } label: {
                        Text("恢复")
                            .foregroundStyle(DS.textSecondary)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.regular)
                    .help("恢复")

                    Menu {
                        Button("恢复") {
                            restore(trashNote)
                        }
                        Divider()
                        Button("永久删除", role: .destructive) {
                            permanentlyDelete(trashNote)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(DS.textSecondary)
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(DS.textSecondary)
                    .menuIndicator(.hidden)
                    .help("更多操作")
                }
            }
        }
    }

    private func trashTitle(for trashNote: TrashNote) -> String {
        if let body = trashNote.body {
            return firstLine(of: body)
        } else if trashNote.isEncrypted {
            return trashNote.title
        } else {
            return "(无内容)"
        }
    }

    private func firstLine(of body: String) -> String {
        NoteTitleFormatter.displayTitle(from: body, emptyTitle: NoteTitleFormatter.emptyTitle)
    }

    private func timeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(
            get: { actionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    actionErrorMessage = nil
                }
            }
        )
    }

    private func restore(_ trashNote: TrashNote) {
        Task {
            do {
                try await vaultStore.restoreTrashNote(trashNote)
            } catch {
                presentActionError(error)
            }
        }
    }

    private func permanentlyDelete(_ trashNote: TrashNote) {
        Task {
            do {
                try await vaultStore.permanentlyDeleteTrashNote(trashNote)
            } catch {
                presentActionError(error)
            }
        }
    }

    private func emptyTrash() {
        Task {
            do {
                try await vaultStore.emptyTrash()
            } catch {
                presentActionError(error)
            }
        }
    }

    private func presentActionError(_ error: Error) {
        actionErrorMessage = error.localizedDescription
        SyncStatusStore.shared.setFailed(message: error.localizedDescription)
    }
}

struct TrashListRow<Trailing: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.s3) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.textStrong)
                    .lineLimit(1)

                Text(subtitle)
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
                    .lineLimit(1)
            }

            Spacer(minLength: DS.s3)

            trailing()
        }
        .padding(.horizontal, DS.s3)
        .padding(.vertical, 10)
        .background(isHovering ? DS.primaryContainer.opacity(0.42) : DS.surfaceCard.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                .stroke(isHovering ? DS.primary.opacity(0.28) : DS.line, lineWidth: 0.5)
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
