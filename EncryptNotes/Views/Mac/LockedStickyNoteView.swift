import Foundation
import SwiftUI

struct LockedStickyNoteView: View {
    let noteInfo: EncryptedNoteInfo
    @ObservedObject private var windowStore = MacNoteWindowStore.shared
    @ObservedObject private var vaultStore = VaultStore.shared
    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(spacing: DS.s4) {
            HStack {
                HStack(spacing: DS.s1) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                    Text("加密")
                        .font(DS.caption())
                }
                .foregroundColor(DS.primary)
                .padding(.horizontal, DS.s2)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                        .fill(DS.primaryContainer)
                )

                Spacer()

                Button(action: { togglePin() }) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .foregroundColor(isPinned ? DS.primary : DS.textSecondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help(isPinned ? "取消置顶" : "置顶")

                Button(action: { showingDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .foregroundColor(DS.textSecondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("移到回收站")
            }
            .padding(.horizontal, DS.s3)
            .padding(.top, DS.s3)

            Spacer()

            VStack(spacing: DS.s3) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 32))
                    .foregroundColor(DS.textSubtle)

                Text("这台 Mac 还没有当前加密空间的密钥。")
                    .font(DS.body())
                    .foregroundColor(DS.textSecondary)
                    .multilineTextAlignment(.center)

                Text("加载密钥文件后，笔记将在本机解密显示。")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
                    .multilineTextAlignment(.center)

                Button("加载密钥文件…") {
                    loadKeyFile()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(DS.primary)
            }
            .padding(.horizontal, DS.s4)

            Spacer()
        }
        .dsStickyNoteWindow()
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("删除这条加密笔记？"),
                message: Text("笔记将移到回收站，加载密钥后可以恢复。"),
                primaryButton: .destructive(Text("删除")) {
                    Task {
                        try? await vaultStore.deleteLockedNote(noteInfo)
                        StickyNoteWindowManager.shared.closeWindow(for: noteInfo.id)
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var isPinned: Bool {
        windowStore.windowState(for: noteInfo.id)?.isPinned ?? true
    }

    private func togglePin() {
        windowStore.togglePin(for: noteInfo.id)
        StickyNoteWindowManager.shared.updateWindowLevel(for: noteInfo.id, isPinned: !isPinned)
    }

    private func loadKeyFile() {
        MacMenuBarController.shared.loadKeyFile()
    }
}
