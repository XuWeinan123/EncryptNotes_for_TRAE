import SwiftUI

enum NoteEditorMode {
    case create
    case edit(Note)
}

struct NoteEditorView: View {
    let mode: NoteEditorMode
    let onSave: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var noteBody: String = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSaving = false

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TextEditor(text: $noteBody)
                        .font(DS.bodyLg())
                        .foregroundColor(DS.textBody)
                        .frame(minHeight: 320)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, DS.cardPadding)
                        .padding(.vertical, DS.cardPadding)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle(isEditing ? "编辑笔记" : "新建笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundColor(DS.textSecondary)
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("保存") {
                            saveNote()
                        }
                        .font(DS.body())
                        .foregroundColor(noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                         ? DS.textSubtle
                                         : DS.primary)
                        .disabled(noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear {
                if case .edit(let note) = mode {
                    noteBody = note.body
                }
            }
            .alert("保存失败", isPresented: $showError) {
                Button("确定") {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func saveNote() {
        guard !noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "正文不能为空"
            showError = true
            return
        }

        isSaving = true
        Task {
            do {
                try await onSave(noteBody)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isSaving = false
        }
    }
}
