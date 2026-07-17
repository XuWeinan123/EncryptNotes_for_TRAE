import Foundation
import SwiftUI
import AppKit

struct AllNotesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var vaultStore = VaultStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var isSearchBarVisible = false
    @State private var actionErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if isSearchBarVisible {
                MacListSearchBar(
                    placeholder: "Search Notes…",
                    text: $searchText,
                    onClose: { hideSearchBar() }
                )
            }

            tagFilters

            if isLoading {
                SWEmptyState(
                    title: "Loading Notes",
                    message: "Notes will appear when syncing and index loading are complete.",
                    systemImage: "tray.full"
                )
                .transition(.opacity)
            } else if filteredNotes.isEmpty {
                SWEmptyState(
                    title: "No Matching Notes",
                    message: emptyStateMessage,
                    systemImage: "magnifyingglass"
                )
                .transition(.opacity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        listSummary

                        ForEach(filteredNotes) { item in
                            noteRow(for: item)
                                .padding(.horizontal, DS.s3)
                                .padding(.vertical, DS.s1)
                                .transition(noteListTransition)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    openNote(item)
                                }
                                .contextMenu {
                                    noteContextMenu(for: item)
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
        .animation(noteListAnimation, value: noteCollectionIDs)
        .safeAreaPadding(.top, DS.s2)
        .background(DS.bg)
        .dsLiquidGlassToolbar()
        .navigationTitle("All Notes")
        .toolbar { allNotesToolbar }
        .background(MacListSearchToolbarAppearance(isActive: isSearchBarVisible))
        .onChange(of: listSnapshot.tagCounts) { _, tagCounts in
            guard let selectedTag else { return }
            if !tagCounts.contains(where: { $0.tag == selectedTag }) {
                self.selectedTag = nil
            }
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
    private var allNotesToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                toggleSearchBar()
            } label: {
                Label("Search", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .help("Search")
            .keyboardShortcut("f", modifiers: .command)
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
            Text(LocalizedStringKey(noteCountText))
                .font(DS.caption())
                .foregroundColor(DS.textSubtle)
                .padding(.top, 8)
//            if listSnapshot.emptyReadableCount > 0 {
//                SWStatusBadge(L10n.string("%lld empty notes", Int64(listSnapshot.emptyReadableCount)), systemImage: "exclamationmark.triangle", style: .warning)
//            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.s3)
        .padding(.top, DS.s3 - DS.s4)
        .padding(.bottom, DS.s2)
    }

    @ViewBuilder
    private var tagFilters: some View {
        let tagCounts = listSnapshot.tagCounts
        if !tagCounts.isEmpty || selectedTag != nil {
            ViewThatFits(in: .horizontal) {
                tagFilterRow(tagCounts: tagCounts, visibleCount: 8)
                tagFilterRow(tagCounts: tagCounts, visibleCount: 7)
                tagFilterRow(tagCounts: tagCounts, visibleCount: 6)
                tagFilterRow(tagCounts: tagCounts, visibleCount: 5)
                tagFilterRow(tagCounts: tagCounts, visibleCount: 4)
                tagFilterRow(tagCounts: tagCounts, visibleCount: 3)
                tagFilterRow(tagCounts: tagCounts, visibleCount: 2)
                tagFilterRow(tagCounts: tagCounts, visibleCount: 1)
                tagFilterRow(tagCounts: tagCounts, visibleCount: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.s3)
            .padding(.bottom, DS.s2)
        }
    }

    private func tagFilterRow(tagCounts: [TagCount], visibleCount: Int) -> some View {
        let visibleTags = Array(tagCounts.prefix(visibleCount))
        let overflowTags = Array(tagCounts.dropFirst(visibleCount))

        return HStack(spacing: DS.s1) {
            SWFilterChip(title: "All", isSelected: selectedTag == nil) {
                selectedTag = nil
            }
            ForEach(visibleTags) { tagCount in
                SWFilterChip(title: tagCount.tag, isSelected: selectedTag == tagCount.tag) {
                    selectedTag = tagCount.tag
                }
            }
            if let selectedTag, !visibleTags.contains(where: { $0.tag == selectedTag }) {
                SWFilterChip(title: selectedTag, isSelected: true) {}
            }
            if !overflowTags.isEmpty {
                SWFilterChipMenu(title: "…", items: overflowTags.map(\.tag)) { tag in
                    selectedTag = tag
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var filteredNotes: [NoteListItem] {
        listSnapshot.items
    }

    private var noteCollectionIDs: [String] {
        vaultStore.readableNotes.map(\.id) + vaultStore.lockedEncryptedNotes.map(\.id)
    }

    private var noteListAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.28, extraBounce: 0)
    }

    private var noteListTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        )
    }

    private var listSnapshot: MacNoteListSnapshot {
        MacNoteListSnapshotBuilder.make(
            readableNotes: vaultStore.readableNotes,
            lockedEncryptedNotes: vaultStore.lockedEncryptedNotes,
            query: searchText,
            selectedTag: selectedTag,
            excludingHexColorsFromTags: settings.excludeHexColorsFromTags,
            titleProvider: { vaultStore.displayTitle(for: $0, emptyTitle: "") }
        )
    }

    private var isLoading: Bool {
        if case .loading = vaultStore.state { return true }
        return false
    }

    private var noteCountText: String {
        guard !isLoading else { return "Loading All Notes" }
        let encryptedCount = listSnapshot.encryptedCount
        if encryptedCount > 0 {
            return L10n.string("%lld notes, %lld encrypted", Int64(listSnapshot.totalCount), Int64(encryptedCount))
        }
        return L10n.string("%lld notes", Int64(listSnapshot.totalCount))
    }

    private var emptyStateMessage: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try another keyword or clear the search."
        }
        if selectedTag != nil {
            return "There are no readable notes with this tag."
        }
        return "Your first note will appear here."
    }

    @ViewBuilder
    private func noteRow(for item: NoteListItem) -> some View {
        switch item {
        case .readable(let note):
            AllNotesListRow(
                title: vaultStore.displayTitle(for: note, emptyTitle: NoteTitleFormatter.emptyTitle),
                subtitle: note.isEncrypted ? "" : notePreview(for: note),
                isLocked: note.isEncrypted,
                timeText: timeString(from: note.createdAt),
                onOpen: { openNote(item) },
                menu: { noteContextMenu(for: item) }
            )

        case .locked(let info):
            AllNotesListRow(
                title: info.title,
                subtitle: "",
                isLocked: true,
                timeText: timeString(from: info.createdAt),
                onOpen: { openNote(item) },
                menu: { noteContextMenu(for: item) }
            )
        }
    }

    @ViewBuilder
    private func noteContextMenu(for item: NoteListItem) -> some View {
        switch item {
        case .readable(let note):
            Button("Rename…") { beginRenaming(note) }
                .disabled(note.isEncrypted)
        case .locked:
            Button("Rename…") {}
                .disabled(true)
        }
        Divider()
        switch item {
        case .readable(let note):
            if note.isEncrypted {
                Button("Convert to Plain Text") { convertToPlain(item) }
            } else {
                Button("Convert to Encrypted") { convertToEncrypted(note) }
            }
        case .locked:
            Button("Convert to Plain Text") { convertToPlain(item) }
        }
        Divider()
        Button("Move to Trash", role: .destructive) {
            deleteNote(item)
        }
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

    private func timeString(from date: Date) -> String {
        DateFormatters.formatNoteListRelativeTime(date)
    }

    private func notePreview(for note: Note) -> String {
        NoteTitleFormatter.displayTitle(from: note.body, emptyTitle: "")
    }

    private func openNote(_ item: NoteListItem) {
        switch item {
        case .readable(let note):
            MacMenuBarController.shared.openStickyNote(for: note)
        case .locked(let info):
            MacMenuBarController.shared.openLockedStickyNote(for: info)
        }
    }

    private func deleteNote(_ item: NoteListItem) {
        Task {
            do {
                switch item {
                case .readable(let note):
                    try await vaultStore.deleteNote(note)
                case .locked(let info):
                    try await vaultStore.deleteLockedNote(info)
                }
            } catch {
                actionErrorMessage = error.localizedDescription
                SyncStatusStore.shared.setFailed(message: error.localizedDescription)
            }
        }
    }

    private func convertToEncrypted(_ note: Note) {
        Task {
            SyncStatusStore.shared.setSyncing()
            do {
                _ = try await vaultStore.encryptNoteForEditing(note, body: note.body)
                SyncStatusStore.shared.setSaved()
            } catch {
                actionErrorMessage = L10n.string("Could not convert to an encrypted note: %@", error.localizedDescription)
                SyncStatusStore.shared.setFailed(message: error.localizedDescription)
            }
        }
    }

    private func convertToPlain(_ item: NoteListItem) {
        Task {
            SyncStatusStore.shared.setSyncing()
            do {
                let encryptedNote: Note
                switch item {
                case .readable(let note):
                    encryptedNote = note
                case .locked(let info):
                    encryptedNote = try await vaultStore.openEncryptedNote(info)
                }
                _ = try await vaultStore.decryptNotePermanently(encryptedNote)
                SyncStatusStore.shared.setSaved()
            } catch {
                actionErrorMessage = L10n.string("Could not convert to a plain-text note: %@", error.localizedDescription)
                SyncStatusStore.shared.setFailed(message: error.localizedDescription)
            }
        }
    }

    private func beginRenaming(_ note: Note) {
        let alert = NSAlert()
        alert.messageText = "Rename Note"
        alert.informativeText = "The title only affects lists, menus, and filenames. It does not change note content."
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.string("Save"))
        alert.addButton(withTitle: L10n.string("Cancel"))

        let titleField = NSTextField(
            string: vaultStore.displayTitle(for: note, emptyTitle: "")
        )
        titleField.placeholderString = "Title"
        titleField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        titleField.selectText(nil)
        alert.accessoryView = titleField

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            guard let cleanedTitle = NoteTitleFormatter.sanitizedGeneratedTitle(titleField.stringValue) else {
                actionErrorMessage = "Enter a valid title."
                return
            }

            Task {
                do {
                    try await vaultStore.renameNote(note, title: cleanedTitle)
                } catch {
                    actionErrorMessage = L10n.string("Rename failed: %@", error.localizedDescription)
                }
            }
        }

        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

}

struct AllNotesListRow<MenuContent: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let title: String
    let subtitle: String
    let isLocked: Bool
    let timeText: String
    let onOpen: () -> Void
    @ViewBuilder let menu: () -> MenuContent

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

            if isHovering {
                HStack(spacing: DS.s1) {
                    Button(action: onOpen) {
                        Text("Open")
                            .foregroundStyle(DS.textSecondary)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.regular)
                    .help("Open")

                    Menu {
                        menu()
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
            } else {
                HStack(spacing: DS.s2) {
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(DS.textSecondary)
                            .frame(width: 22, height: 22)
                            .background(DS.surfaceSunken)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(DS.line, lineWidth: 0.5))
                    }

                    Text(timeText)
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)
                        .monospacedDigit()
                }
            }
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

struct MacListSearchBar: View {
    let placeholder: String
    @Binding var text: String
    let onClose: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: DS.s2) {
            HStack(spacing: DS.s2) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(DS.textSubtle)

                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(DS.body())
                    .focused($isFocused)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(DS.textSubtle)
                    }
                    .buttonStyle(.plain)
                    .help("Clear Search")
                }
            }
            .padding(.horizontal, DS.s3)
            .padding(.vertical, DS.s2)
            .dsInputSurface(cornerRadius: DS.rMd)

            Button {
                onClose()
            } label: {
                Label("Close Search", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .foregroundColor(DS.textSecondary)
            .help("Close Search")
        }
        .padding(.horizontal, DS.s3)
        .padding(.vertical, DS.s2)
//        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.line)
                .frame(height: 0.5)
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onExitCommand {
            onClose()
        }
    }
}

struct MacListSearchToolbarAppearance: NSViewRepresentable {
    let isActive: Bool

    func makeNSView(context: Context) -> MacListSearchToolbarAppearanceView {
        let view = MacListSearchToolbarAppearanceView()
        view.isActive = isActive
        return view
    }

    func updateNSView(_ nsView: MacListSearchToolbarAppearanceView, context: Context) {
        nsView.isActive = isActive
        nsView.apply()
    }

    static func dismantleNSView(_ nsView: MacListSearchToolbarAppearanceView, coordinator: ()) {
        nsView.isActive = false
        nsView.apply()
    }
}

final class MacListSearchToolbarAppearanceView: NSView {
    var isActive = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    func apply() {
        guard let window else { return }
        window.titlebarAppearsTransparent = !isActive
        window.backgroundColor = isActive ? .white : .textBackgroundColor
        window.titlebarSeparatorStyle = isActive ? .line : .automatic
    }
}
