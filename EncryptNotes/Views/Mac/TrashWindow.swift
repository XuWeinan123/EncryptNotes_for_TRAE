import Foundation
import SwiftUI

struct TrashView: View {
    @ObservedObject private var vaultStore = VaultStore.shared
    @State private var showingEmptyTrashConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("回收站")
                    .font(DS.title())
                    .foregroundColor(DS.textEmphasize)
                Spacer()
                Button("清空回收站", role: .destructive) {
                    showingEmptyTrashConfirmation = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(vaultStore.trashNotes.isEmpty)
            }
            .padding(DS.s3)
            .background(DS.surfaceRaised)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DS.line)
                    .frame(height: 0.5)
            }

            List {
                if vaultStore.trashNotes.isEmpty {
                    emptyRow
                        .listRowInsets(EdgeInsets(top: DS.s3, leading: DS.s3, bottom: DS.s3, trailing: DS.s3))
                        .listRowSeparator(.hidden)
                        .listRowBackground(DS.bg)
                } else {
                    ForEach(vaultStore.trashNotes) { trashNote in
                        trashRow(for: trashNote)
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
        .alert("确认清空回收站？", isPresented: $showingEmptyTrashConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                Task {
                    try? await vaultStore.emptyTrash()
                }
            }
        } message: {
            Text("回收站中的所有笔记将被永久删除，无法恢复。")
        }
    }

    private var emptyRow: some View {
        VStack(spacing: DS.s2) {
            Image(systemName: "trash")
                .font(.system(size: 28, weight: .regular))
                .foregroundColor(DS.textSubtle)
            Text("回收站为空")
                .font(DS.body())
                .foregroundColor(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.s6)
        .dsInputSurface()
    }

    @ViewBuilder
    private func trashRow(for trashNote: TrashNote) -> some View {
        HStack(alignment: .top, spacing: DS.s3) {
            Image(systemName: trashNote.isEncrypted ? "lock.fill" : "doc.text")
                .foregroundColor(trashNote.isEncrypted ? DS.primaryDeep : DS.textSubtle)
                .font(.system(size: 12))
                .frame(width: 18)
                .padding(.top, DS.s1)

            VStack(alignment: .leading, spacing: DS.s1) {
                if let body = trashNote.body {
                    Text(firstLine(of: body))
                        .font(DS.body())
                        .foregroundColor(DS.textStrong)
                        .lineLimit(1)
                } else if trashNote.isEncrypted {
                    Text("加密笔记")
                        .font(DS.body())
                        .foregroundColor(DS.textSecondary)
                } else {
                    Text("(无内容)")
                        .font(DS.body())
                        .foregroundColor(DS.textSubtle)
                }

                Text("删除于 \(timeString(from: trashNote.deletedAt))")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
            }

            Spacer()

            HStack(spacing: DS.s1) {
                Button("恢复") {
                    Task {
                        try? await vaultStore.restoreTrashNote(trashNote)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("永久删除", role: .destructive) {
                    Task {
                        try? await vaultStore.permanentlyDeleteTrashNote(trashNote)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, DS.s2)
        .padding(.vertical, DS.s2)
        .dsInputSurface()
    }

    private func firstLine(of body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "(空笔记)" }
        return String(trimmed.components(separatedBy: .newlines).first { !$0.isEmpty } ?? "(空笔记)")
    }

    private func timeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
