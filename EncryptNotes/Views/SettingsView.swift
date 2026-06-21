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
                        Spacer()
                        Text(vaultStore.isUnlocked ? "已解锁" : "已锁定")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("iCloud", systemImage: "icloud")
                        Spacer()
                        Text(ICloudVaultStorage.shared.isAvailable ? "可用" : "不可用")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("密钥") {
                    Button {
                        exportKey()
                    } label: {
                        Label("导出密钥文件", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!vaultStore.isUnlocked)
                }

                Section("操作") {
                    Button {
                        vaultStore.lock()
                        dismiss()
                    } label: {
                        Label("锁定 App", systemImage: "lock")
                    }
                    .disabled(!vaultStore.isUnlocked)

                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("重置加密空间", systemImage: "trash")
                    }
                }

                Section {
                    HStack {
                        Label("版本", systemImage: "info.circle")
                        Spacer()
                        Text("v0.1")
                            .foregroundStyle(.secondary)
                    }

                    if purchaseStore.isPro {
                        HStack {
                            Label("Pro", systemImage: "star.fill")
                            Spacer()
                            Text("已激活")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                Label("升级 Pro", systemImage: "star")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
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
    static var readableContentTypes: [UTType] { [.json] }

    let url: URL

    init(url: URL) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadCorruptFile)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(url: url)
    }
}
