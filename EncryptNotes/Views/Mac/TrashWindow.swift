import Foundation
import SwiftUI

struct TrashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var vaultStore = VaultStore.shared
    @State private var showingEmptyTrashConfirmation = false
    @State private var searchText = ""
    @State private var isSearchBarVisible = false
    @State private var actionErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if isSearchBarVisible {
                MacListSearchBar(
                    placeholder: "Search Trash…",
                    text: $searchText,
                    onClose: { hideSearchBar() }
                )
            }

            if filteredTrashNotes.isEmpty {
                emptyRow
                    .transition(.opacity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        listSummary

                        ForEach(filteredTrashNotes) { trashNote in
                            trashRow(for: trashNote)
                                .padding(.horizontal, DS.s3)
                                .padding(.vertical, DS.s1)
                                .transition(trashListTransition)
                                .contextMenu {
                                    Button("Restore") {
                                        restore(trashNote)
                                    }
                                    Button("Delete Permanently", role: .destructive) {
                                        permanentlyDelete(trashNote)
                                    }
                                }
                        }

                        Color.clear
                            .frame(height: DS.s3)
                            .accessibilityHidden(true)
                    }
                }
                .background(DS.bg)
                .transition(.opacity)
            }
        }
        .animation(trashListAnimation, value: vaultStore.trashNotes.map(\.id))
        .background(DS.bg)
        .dsLiquidGlassToolbar()
        .navigationTitle("Trash")
        .toolbar { trashToolbar }
        .background(MacListSearchToolbarAppearance(isActive: isSearchBarVisible))
        .alert("Empty Trash?", isPresented: $showingEmptyTrashConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Empty", role: .destructive) {
                emptyTrash()
            }
        } message: {
            Text("All notes in Trash will be permanently deleted and cannot be recovered.")
        }
        .alert("Operation Failed", isPresented: actionErrorBinding) {
            Button("OK") {
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
                Label("Search", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .help("Search")
            .keyboardShortcut("f", modifiers: .command)

            Button(role: .destructive) {
                showingEmptyTrashConfirmation = true
            } label: {
                Label("Empty", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .disabled(vaultStore.trashNotes.isEmpty)
            .help(vaultStore.trashNotes.isEmpty ? "Trash Is Empty" : "Permanently delete all notes in Trash")
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
            Text(L10n.string("%lld notes in Trash", Int64(filteredTrashNotes.count)))
                .font(DS.caption())
                .foregroundColor(DS.textSubtle)
            Text(vaultStore.trashNotes.isEmpty ? "No Deleted Notes" : "Deleted notes are kept for 30 days")
                .font(DS.caption())
                .foregroundColor(DS.textSubtle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.s3)
        .padding(.top, DS.s3 - DS.s4)
        .padding(.bottom, DS.s2)
        .padding(.top, 8)
    }

    private var filteredTrashNotes: [TrashNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return vaultStore.trashNotes }
        return vaultStore.trashNotes.filter { trashNote in
            trashTitle(for: trashNote).localizedCaseInsensitiveContains(query)
                || trashNote.body?.localizedCaseInsensitiveContains(query) == true
        }
    }

    private var trashListAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.28, extraBounce: 0)
    }

    private var trashListTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        )
    }

    private var emptyRow: some View {
        SWEmptyState(
            title: vaultStore.trashNotes.isEmpty ? "Trash Is Empty" : "No Matching Notes",
            message: vaultStore.trashNotes.isEmpty ? "Deleted notes are kept here for 30 days" : "Try another keyword or clear the search.",
            systemImage: "trash"
        )
    }

    @ViewBuilder
    private func trashRow(for trashNote: TrashNote) -> some View {
        TrashListRow(
            title: trashTitle(for: trashNote),
            subtitle: trashNote.isEncrypted ? "" : trashNote.body.map(notePreview) ?? ""
        ) {
            HStack(spacing: DS.s4) {
                HStack(spacing: DS.s2) {
                    if trashNote.isEncrypted {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(DS.textSecondary)
                            .frame(width: 22, height: 22)
                            .background(DS.surfaceSunken)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(DS.line, lineWidth: 0.5))
                    }
                    SWStatusBadge(L10n.string("%lld days", Int64(trashNote.remainingDays)), systemImage: "clock", style: .warning)
                }

                Menu {
                    Button("Restore") {
                        restore(trashNote)
                    }
                    Divider()
                    Button("Delete Permanently", role: .destructive) {
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
                .help("More Actions")
            }
        }
    }

    private func trashTitle(for trashNote: TrashNote) -> String {
        if let body = trashNote.body {
            return firstLine(of: body)
        } else if trashNote.isEncrypted {
            return trashNote.title
        } else {
            return "(No Content)"
        }
    }

    private func notePreview(_ body: String) -> String {
        NoteTitleFormatter.displayTitle(from: body, emptyTitle: "")
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
                Text(LocalizedStringKey(title))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.textStrong)
                    .lineLimit(1)

                if !subtitle.isEmpty {
                    Text(LocalizedStringKey(subtitle))
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DS.s3)

            trailing()
        }
        .padding(.horizontal, DS.s3)
        .padding(.vertical, 10)
        .frame(minHeight: 58)
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
