import SwiftUI

enum NoteEditorMode {
    case create
    case edit(Note)
}

struct NoteEditorView: View {
    let mode: NoteEditorMode
    let onSave: (String, String, [String]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var body: String = ""
    @State private var tagsText: String = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("可选，默认从正文生成", text: $title)
                        .textFieldStyle(.plain)
                }

                Section("正文") {
                    TextEditor(text: $body)
                        .frame(minHeight: 200)
                        .scrollContentBackground(.hidden)
                }

                Section("标签") {
                    TextField("用逗号分隔，如: 工作,重要", text: $tagsText)
                        .textFieldStyle(.plain)
                }
            }
            .navigationTitle(isEditing ? "编辑笔记" : "新建笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            saveNote()
                        }
                    }
                    .disabled(body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if case .edit(let note) = mode {
                    title = note.title
                    body = note.body
                    tagsText = note.tags.joined(separator: ",")
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
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "正文不能为空"
            showError = true
            return
        }

        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        onSave(title, body, tags)
        dismiss()
    }
}
