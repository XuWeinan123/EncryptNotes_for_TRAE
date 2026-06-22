import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var vaultStore = VaultStore.shared
    @StateObject private var purchaseStore = PurchaseStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showKeyExporter = false
    @State private var showResetConfirmation = false
    @State private var showPaywall = false
    @State private var exportedKeyURL: URL?

    var body: some View {
        NavigationStack {
            List {
                Section("状态") {
                    HStack {
                        Label("加密空间", systemImage: "lock.fill")
                            .foregroundColor(DS.textBody)
                        Spacer()
                        Text(vaultStore.isUnlocked ? "已解锁" : "已锁定")
                            .font(DS.body())
                            .foregroundColor(DS.textSecondary)
                    }

                    HStack {
                        Label("iCloud", systemImage: "icloud")
                            .foregroundColor(DS.textBody)
                        Spacer()
                        Text(ICloudVaultStorage.shared.isAvailable ? "可用" : "不可用")
                            .font(DS.body())
                            .foregroundColor(DS.textSecondary)
                    }
                }

                Section("密钥") {
                    Button {
                        exportKey()
                    } label: {
                        Label("导出密钥文件", systemImage: "square.and.arrow.up")
                            .foregroundColor(DS.textBody)
                    }
                    .disabled(!vaultStore.isUnlocked)
                }

                Section("操作") {
                    Button {
                        vaultStore.lock()
                        dismiss()
                    } label: {
                        Label("锁定 App", systemImage: "lock")
                            .foregroundColor(DS.textBody)
                    }
                    .disabled(!vaultStore.isUnlocked)

                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("重置加密空间", systemImage: "trash")
                            .foregroundColor(DS.destructive)
                    }
                }

                Section {
                    HStack {
                        Label("版本", systemImage: "info.circle")
                            .foregroundColor(DS.textBody)
                        Spacer()
                        Text("v0.1")
                            .font(DS.body())
                            .foregroundColor(DS.textSecondary)
                    }

                    if purchaseStore.isPro {
                        HStack {
                            Label("PRO", systemImage: "star.fill")
                                .foregroundColor(DS.pro)
                            Spacer()
                            Text("已激活")
                                .font(DS.body())
                                .foregroundColor(DS.textSecondary)
                        }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                Label("升级 PRO", systemImage: "star")
                                    .foregroundColor(DS.pro)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(DS.textSubtle)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundColor(DS.primary)
                }
            }
            .fileExporter(
                isPresented: $showKeyExporter,
                document: exportedKeyURL.map { KeyFileDocument(url: $0) },
                contentType: UTType(filenameExtension: "bkwkey") ?? .json,
                defaultFilename: "my-vault-key.bkwkey"
            ) { result in
                switch result {
                case .success:
                    break
                case .failure:
                    break
                }
            }
            .alert("重置加密空间", isPresented: $showResetConfirmation) {
                Button("取消", role: .cancel) {}
                Button("重置", role: .destructive) {
                    Task {
                        do {
                            try await vaultStore.resetVault()
                            withAnimation(.easeInOut(duration: 0.3)) {
                                dismiss()
                            }
                        } catch {
                            vaultStore.lastError = "重置失败：\(error.localizedDescription)"
                        }
                    }
                }
            } message: {
                Text("重置后，当前 iCloud 中的加密笔记文件将被清空。\n如果你没有旧密钥文件，这些笔记将无法恢复。")
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
        }
    }

    private func exportKey() {
        do {
            exportedKeyURL = try vaultStore.exportKeyFile()
            showKeyExporter = true
        } catch {
            // Handle error
        }
    }
}

struct KeyFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "bkwkey") ?? .json] }

    let url: URL

    init(url: URL) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadCorruptFile)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url)
    }
}
