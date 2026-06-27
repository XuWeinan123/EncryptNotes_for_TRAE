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
            .padding(.top, 80)
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
        .background(Color(nsColor: .textBackgroundColor))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Text("加密笔记")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)

                Button(action: {}) {
                    Label("加密笔记", systemImage: "lock.fill")
                }
                .labelStyle(.iconOnly)
                .controlSize(.large)
                .disabled(true)
                .help("加密笔记")
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingDeleteConfirmation = true }) {
                    Label("移到回收站", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .controlSize(.large)
                .help("移到回收站")
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: { togglePin() }) {
                    Label(isPinned ? "取消置顶" : "置顶",
                          systemImage: isPinned ? "pin.fill" : "pin")
                }
                .labelStyle(.iconOnly)
                .controlSize(.large)
                .help(isPinned ? "取消置顶" : "置顶")
            }
        }
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
