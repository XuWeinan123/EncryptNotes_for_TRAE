import Foundation
import SwiftUI

struct LockedStickyNoteView: View {
    let noteInfo: EncryptedNoteInfo
    @ObservedObject private var windowStore = MacNoteWindowStore.shared
    @ObservedObject private var vaultStore = VaultStore.shared
    @ObservedObject private var syncStore = SyncStatusStore.shared
    @State private var showingDeleteConfirmation = false

    private var isPinned: Bool {
        windowStore.windowState(for: noteInfo.id)?.isPinned ?? true
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.s2) {
                Button(action: {
                    StickyNoteWindowManager.shared.closeWindow(for: noteInfo.id)
                }) {
                    Image(systemName: "xmark")
                        .foregroundColor(DS.textSecondary)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help("关闭")

                Spacer()

                Button(action: {}) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(DS.primary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help("加密笔记")

                Rectangle()
                    .fill(DS.line)
                    .frame(width: 0.5, height: 14)
                    .padding(.horizontal, DS.s1)

                Button(action: { showingDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .foregroundColor(DS.textSecondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("移到回收站")

                Button(action: { togglePin() }) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .foregroundColor(isPinned ? DS.primary : DS.textSecondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help(isPinned ? "取消置顶" : "置顶")
            }
            .padding(.horizontal, DS.s4)
            .padding(.top, DS.s3)
            .padding(.bottom, DS.s1)
            .frame(minHeight: 40)
            .background(MacWindowDragRegion())

            VStack(spacing: DS.s3) {
                Spacer()

                Image(systemName: "lock.shield")
                    .font(.system(size: 28))
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

                Spacer()
            }
            .padding(.horizontal, DS.s4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !syncStore.isNetworkAvailable {
                HStack {
                    Spacer()
                    Text("无网络")
                        .font(DS.caption())
                        .foregroundColor(DS.destructive)
                }
                .padding(.horizontal, DS.s3)
                .padding(.top, DS.s1)
                .padding(.bottom, DS.s2)
            } else {
                Spacer()
                    .frame(height: DS.s2)
            }
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

    private func togglePin() {
        let newPinned = !isPinned
        windowStore.setPinned(newPinned, for: noteInfo.id)
        StickyNoteWindowManager.shared.updateWindowLevel(for: noteInfo.id, isPinned: newPinned)
    }

    private func loadKeyFile() {
        MacMenuBarController.shared.loadKeyFile()
    }
}
