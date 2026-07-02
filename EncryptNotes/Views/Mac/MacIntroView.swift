import SwiftUI
import AppKit

struct MacIntroView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var shortcutStore = ShortcutStore.shared

    let onClose: () -> Void

    init(onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
    }

    private var newNoteShortcut: String {
        ShortcutStore.displayStringForKey(
            keyCode: shortcutStore.newNoteKey.keyCode,
            modifiers: shortcutStore.newNoteKey.modifiers
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: DS.s6) {
                logo

                VStack(spacing: DS.s2) {
                    Text("Seal Note")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(DS.textEmphasize)

                    Text("快速记录，不打断当前工作。")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(DS.textSecondary)
                }
            }
            .padding(.top, 76)
            .padding(.bottom, DS.s8)

            VStack(alignment: .leading, spacing: DS.s6) {
                introRow(systemImage: "menubar.rectangle", title: "菜单栏便签", text: "从右上角菜单快速新建、打开最近笔记。")
                introRow(systemImage: "doc.plaintext", title: "Markdown 文件", text: "每条笔记都是可同步、可迁移的 Markdown 文件。")
                introRow(systemImage: "lock.shield", title: "正文加密", text: "加密笔记只加密正文，密钥来自你选择的 .bkwkey 文件。")
            }
            .frame(width: 460, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)

            Text("通过右上角菜单栏图标，或按 \(newNoteShortcut) 新建笔记。")
                .font(DS.bodyLg())
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            .padding(.horizontal, 64)
            .padding(.top, DS.s8)

            Spacer(minLength: DS.s8)

            VStack(spacing: DS.s3) {
                Button {
                    onClose()
                } label: {
                    Text("关闭")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 104, height: 34)
                        .background(DS.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)

                Toggle("不再显示", isOn: $settings.hideMacIntroOnLaunch)
                    .toggleStyle(.checkbox)
                    .font(DS.body())
                    .foregroundStyle(DS.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 64)
            .padding(.top, 38)
            .padding(.bottom, 84)
            .background(DS.surfaceCard)
        }
        .frame(width: 620, height: 720)
        .background(DS.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(DS.line, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var logo: some View {
        if let image = NSApp.applicationIconImage, image.isValid {
            Image(nsImage: image)
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: DS.floatShadow.color, radius: DS.floatShadow.radius, x: DS.floatShadow.x, y: DS.floatShadow.y)
        } else {
            Image(systemName: "pencil")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(DS.primaryDeep)
                .frame(width: 96, height: 96)
                .background(DS.primaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: DS.floatShadow.color, radius: DS.floatShadow.radius, x: DS.floatShadow.x, y: DS.floatShadow.y)
        }
    }

    private func introRow(systemImage: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: DS.s4) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                    .fill(DS.primaryContainer)
                    .frame(width: 42, height: 42)

                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.primaryDeep)
            }

            VStack(alignment: .leading, spacing: DS.s2) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.textStrong)

                Text(text)
                    .font(DS.bodyLg())
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    MacIntroView()
}
