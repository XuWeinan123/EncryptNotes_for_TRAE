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

                    Text("Capture quickly without interrupting your work.")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(DS.textSecondary)
                }
            }
            .padding(.top, 76)
            .padding(.bottom, DS.s8)

            VStack(alignment: .leading, spacing: DS.s6) {
                introRow(
                    systemImage: "menubar.rectangle",
                    title: Text("Quick Capture"),
                    description: Text("Create or open recent notes from the menu bar without interrupting your work.")
                )
                introRow(
                    systemImage: "doc.plaintext",
                    title: Text("Portable by Design"),
                    description: Text("Save as standard Markdown files for easy sync, migration, and use across tools.")
                )
                introRow(
                    systemImage: "lock.shield",
                    title: Text("On-Device Encryption"),
                    description: Text("On-device encryption with a key file you own and manage.")
                )
            }
            .frame(width: 460, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)

            Text("Use the menu bar icon or press \(newNoteShortcut) to create a note.")
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
                    Text("Close")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 104, height: 34)
                        .background(DS.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)

                Toggle("Do Not Show Again", isOn: $settings.hideMacIntroOnLaunch)
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

    private func introRow(systemImage: String, title: Text, description: Text) -> some View {
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
                title
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.textStrong)

                description
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
