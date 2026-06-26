import Foundation
import SwiftUI
import AppKit
import Combine

struct StickyNoteEditorView: View {
    @StateObject private var viewModel: StickyNoteEditorViewModel
    @ObservedObject private var syncStore = SyncStatusStore.shared
    @Environment(\.dismiss) private var dismiss

    init(note: Note) {
        _viewModel = StateObject(wrappedValue: StickyNoteEditorViewModel(note: note))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.s2) {
                PlainStatusBadge(isEncrypted: viewModel.note.isEncrypted)

                Spacer()

                Button(action: { viewModel.togglePin() }) {
                    Image(systemName: viewModel.isPinned ? "pin.fill" : "pin")
                        .foregroundColor(viewModel.isPinned ? DS.primary : DS.textSecondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help(viewModel.isPinned ? "取消置顶" : "置顶")

                Button(action: { viewModel.deleteNote() }) {
                    Image(systemName: "trash")
                        .foregroundColor(DS.textSecondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("移到回收站")
            }
            .padding(.horizontal, DS.s3)
            .padding(.top, DS.s2)
            .padding(.bottom, DS.s1)

            MacTextView(text: $viewModel.text, onCommit: {})
                .padding(.horizontal, DS.s3)
                .padding(.bottom, DS.s3)

            HStack {
                Text(syncStore.status.displayText)
                    .font(DS.caption())
                    .foregroundColor(syncStatusColor)

                Spacer()

                Text(viewModel.lastSavedText)
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
            }
            .padding(.horizontal, DS.s3)
            .padding(.bottom, DS.s2)
        }
        .dsStickyNoteWindow()
        .alert(isPresented: $viewModel.showingDeleteConfirmation) {
            Alert(
                title: Text("删除这条笔记？"),
                message: Text("笔记将移到回收站，可以恢复。"),
                primaryButton: .destructive(Text("删除")) {
                    viewModel.confirmDelete()
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var syncStatusColor: Color {
        switch syncStore.status {
        case .saved: return DS.textSecondary
        case .syncing: return DS.link
        case .failed: return DS.destructive
        }
    }
}

@MainActor
final class StickyNoteEditorViewModel: ObservableObject {
    @Published var note: Note
    @Published var text: String
    @Published var isPinned: Bool
    @Published var showingDeleteConfirmation = false
    @Published var lastSavedText: String = ""

    private let vaultStore = VaultStore.shared
    private let windowStore = MacNoteWindowStore.shared
    private let syncStore = SyncStatusStore.shared
    private var saveTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(note: Note) {
        self.note = note
        self.text = note.body
        self.isPinned = windowStore.windowState(for: note.id)?.isPinned ?? true
        updateLastSavedText()

        $text
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.save()
            }
            .store(in: &cancellables)

        $isPinned
            .sink { [weak self] newValue in
                guard let self = self else { return }
                self.windowStore.setPinned(newValue, for: self.note.id)
                StickyNoteWindowManager.shared.updateWindowLevel(for: self.note.id, isPinned: newValue)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .macTextViewDidEndEditing)
            .sink { [weak self] _ in
                self?.saveImmediately()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .macWindowWillClose)
            .sink { [weak self] notification in
                guard let self = self,
                      let noteId = notification.userInfo?["noteId"] as? String,
                      noteId == self.note.id else { return }
                self.saveImmediately()
            }
            .store(in: &cancellables)
    }

    func togglePin() {
        isPinned.toggle()
    }

    func deleteNote() {
        showingDeleteConfirmation = true
    }

    func confirmDelete() {
        Task {
            do {
                try await vaultStore.deleteNote(note)
                StickyNoteWindowManager.shared.closeWindow(for: note.id)
            } catch {
                // Error handled by store
            }
        }
    }

    func save() {
        guard text != note.body else {
            syncStore.setSaved()
            return
        }

        saveTask?.cancel()

        syncStore.setSyncing()
        let bodyToSave = text
        let noteToUpdate = note

        saveTask = Task {
            do {
                try await vaultStore.updateNote(noteToUpdate, body: bodyToSave)
                if let updatedNote = vaultStore.readableNotes.first(where: { $0.id == noteToUpdate.id }) {
                    note = updatedNote
                }
                updateLastSavedText()
                syncStore.setSaved()
            } catch {
                syncStore.setFailed(message: error.localizedDescription)
            }
        }
    }

    func saveImmediately() {
        saveTask?.cancel()
        save()
    }

    private func updateLastSavedText() {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        lastSavedText = "已保存 \(formatter.string(from: note.updatedAt))"
    }
}

extension Notification.Name {
    static let macTextViewDidEndEditing = Notification.Name("macTextViewDidEndEditing")
    static let macWindowWillClose = Notification.Name("macWindowWillClose")
}

private class AutoFocusTextView: NSTextView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }
            if window.firstResponder != self {
                window.makeFirstResponder(self)
            }
        }
    }
}

struct MacTextView: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = AutoFocusTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor(DS.textBody)
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        textView.string = text

        context.coordinator.textView = textView

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text && !context.coordinator.isUpdating {
            context.coordinator.isUpdating = true
            textView.string = text
            context.coordinator.isUpdating = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacTextView
        weak var textView: NSTextView?
        var isUpdating = false

        init(_ parent: MacTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isUpdating else { return }
            isUpdating = true
            parent.text = textView.string
            isUpdating = false
        }

        func textDidEndEditing(_ notification: Notification) {
            NotificationCenter.default.post(name: .macTextViewDidEndEditing, object: nil)
        }
    }
}
