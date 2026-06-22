import SwiftUI

struct ResetVaultView: View {
    @StateObject private var vaultStore = VaultStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showFirstConfirmation = false
    @State private var showSecondConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: DS.s6) {
                Spacer(minLength: DS.s8)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundColor(DS.destructive)

                VStack(spacing: DS.s3) {
                    Text("重置加密空间")
                        .font(DS.title())
                        .foregroundColor(DS.textEmphasize)

                    Text("重置后，当前 iCloud 中的加密笔记文件将被清空。\n如果你没有旧密钥文件，这些笔记将无法恢复。")
                        .font(DS.body())
                        .foregroundColor(DS.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, DS.s6)

                VStack(spacing: DS.s4) {
                    Button {
                        showFirstConfirmation = true
                    } label: {
                        Text("重置加密空间")
                            .font(DS.body())
                            .foregroundColor(DS.textEmphasize)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(DS.destructive)
                            .clipShape(RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 40)
                }

                Spacer(minLength: DS.s8)
            }
            .frame(maxWidth: .infinity, minHeight: 600)
        }
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle("重置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .alert("确认重置", isPresented: $showFirstConfirmation) {
            Button("取消", role: .cancel) {}
            Button("继续", role: .destructive) {
                showSecondConfirmation = true
            }
        } message: {
            Text("此操作不可撤销。所有笔记将被永久删除。")
        }
        .alert("最终确认", isPresented: $showSecondConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认重置", role: .destructive) {
                Task {
                    do {
                        try await vaultStore.resetVault()
                        dismiss()
                    } catch {
                        vaultStore.lastError = "重置失败：\(error.localizedDescription)"
                    }
                }
            }
        } message: {
            Text("确定要删除所有笔记并创建新的加密空间吗？")
        }
    }
}
