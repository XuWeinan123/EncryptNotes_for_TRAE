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
                VStack(alignment: .leading, spacing: DS.s3) {
                    Text(isEditing ? "继续整理这条想法" : "快速记下一闪而过的想法")
                        .font(DS.caption())
                        .foregroundColor(DS.textSecondary)

                    TextEditor(text: $noteBody)
                        .font(DS.bodyLg())
                        .foregroundColor(DS.textBody)
                        .frame(minHeight: 320)
                        .scrollContentBackground(.hidden)
                        .padding(DS.cardPadding)
                        .dsInputSurface()

                    HStack(spacing: DS.s1) {
                        Text("用")
                        Text("#tag")
                            .foregroundColor(DS.primary)
                        Text("把想法连接起来")
                    }
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
                }
                .padding(.horizontal, DS.cardPadding)
                .padding(.top, DS.s4)
                .padding(.bottom, DS.s8)
                .frame(maxWidth: DS.contentMax, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .dsCanvasBackground()
            .navigationTitle(isEditing ? "编辑笔记" : "新建笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("保存") {
                            saveNote()
                        }
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
