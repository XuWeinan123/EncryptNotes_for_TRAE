import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct MacSettingsView: View {
    @ObservedObject private var shortcutStore = ShortcutStore.shared
    @ObservedObject private var vaultStore = VaultStore.shared
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("通用", systemImage: "gear")
                }

            shortcutTab
                .tabItem {
                    Label("快捷键", systemImage: "keyboard")
                }

            keyTab
                .tabItem {
                    Label("密钥", systemImage: "key")
                }
        }
        .padding(DS.s4)
        .frame(width: 460, height: 360)
        .background(DS.bg)
    }

    private var generalTab: some View {
        panelStack {
            macPanel("隐私保护") {
                toggleRow("进入后台时隐藏内容", isOn: $settings.hideContentOnBackground)
                toggleRow("回到前台时自动卸载密钥", isOn: $settings.autoUnloadKeyOnForeground)
                helperText("自动卸载密钥不会删除笔记，只会让加密笔记回到乱码状态。")
            }
        }
    }

    private var shortcutTab: some View {
        panelStack {
            macPanel("新建笔记") {
                shortcutRow(
                    title: "新建笔记",
                    value: ShortcutStore.displayStringForKey(
                        keyCode: shortcutStore.newNoteKey.keyCode,
                        modifiers: shortcutStore.newNoteKey.modifiers
                    )
                )
                helperText("默认快捷键：⌃⌘Z")
            }
        }
    }

    private var keyTab: some View {
        panelStack {
            if vaultStore.isKeyLoaded {
                macPanel("密钥状态") {
                    statusRow("密钥已加载到本机", systemImage: "checkmark.shield.fill", tint: DS.primary)

                    Button("导出密钥文件…") {
                        exportKey()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("移除本机密钥", role: .destructive) {
                        unloadKey()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                macPanel("密钥状态") {
                    statusRow("本机未加载密钥", systemImage: "lock.shield", tint: DS.textSubtle)
                    helperText("密钥文件只会在本机读取，不会上传。")

                    Button("加载密钥文件…") {
                        loadKey()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("创建新的加密空间…") {
                        createNewKey()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(DS.primary)
                }
            }
        }
    }

    private func panelStack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.s3) {
                content()
            }
            .padding(.top, DS.s3)
            .padding(.horizontal, DS.s1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(DS.bg)
    }

    private func macPanel<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.s3) {
            Text(title)
                .font(DS.title())
                .foregroundColor(DS.textEmphasize)
            content()
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCardSurface()
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(DS.bodyLg())
            .foregroundColor(DS.textBody)
            .toggleStyle(.switch)
            .padding(.vertical, DS.s1)
    }

    private func shortcutRow(title: String, value: String) -> some View {
        HStack(spacing: DS.s3) {
            Text(title)
                .font(DS.bodyLg())
                .foregroundColor(DS.textBody)
            Spacer()
            Text(value)
                .font(DS.caption())
                .foregroundColor(DS.textSecondary)
            Button("录制…") {
                // Shortcut recording UI can be added here in future
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, DS.s1)
    }

    private func statusRow(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: DS.s2) {
            Image(systemName: systemImage)
                .foregroundColor(tint)
            Text(title)
                .font(DS.bodyLg())
                .foregroundColor(DS.textBody)
        }
    }

    private func helperText(_ text: String) -> some View {
        Text(text)
            .font(DS.caption())
            .foregroundColor(DS.textSubtle)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func loadKey() {
        MacMenuBarController.shared.loadKeyFile()
    }

    private func unloadKey() {
        let alert = NSAlert()
        alert.messageText = "移除本机密钥？"
        alert.informativeText = "移除后，所有加密笔记将无法查看，直到重新加载密钥。"
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                try? await vaultStore.unloadKey()
                StickyNoteWindowManager.shared.closeAllWindows()
            }
        }
    }

    private func exportKey() {
        do {
            let keyURL = try vaultStore.exportKeyFile()
            let panel = NSSavePanel()
            panel.title = "导出密钥文件"
            panel.message = "请将密钥文件保存到安全的位置。"
            panel.nameFieldStringValue = keyURL.lastPathComponent
            panel.allowedContentTypes = [.init(filenameExtension: "bkwkey")!]
            if panel.runModal() == .OK, let saveURL = panel.url {
                try? FileManager.default.copyItem(at: keyURL, to: saveURL)
            }
            try? FileManager.default.removeItem(at: keyURL)
        } catch {
            let alert = NSAlert()
            alert.messageText = "导出失败"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }

    private func createNewKey() {
        let alert = NSAlert()
        alert.messageText = "创建新的加密空间？"
        alert.informativeText = "将生成新的密钥，你需要妥善保存密钥文件。如果 iCloud 中已有加密笔记，将无法使用新密钥解锁。"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                do {
                    try await vaultStore.createKey()
                    let keyURL = try vaultStore.exportKeyFile()
                    let savePanel = NSSavePanel()
                    savePanel.title = "保存密钥文件"
                    savePanel.message = "请立即将密钥文件保存到安全的位置。丢失密钥将无法解密加密笔记。"
                    savePanel.nameFieldStringValue = keyURL.lastPathComponent
                    savePanel.allowedContentTypes = [.init(filenameExtension: "bkwkey")!]
                    if savePanel.runModal() == .OK, let saveURL = savePanel.url {
                        try? FileManager.default.copyItem(at: keyURL, to: saveURL)
                    }
                    try? FileManager.default.removeItem(at: keyURL)
                } catch {
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "创建失败"
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.addButton(withTitle: "确定")
                    errorAlert.runModal()
                }
            }
        }
    }
}
