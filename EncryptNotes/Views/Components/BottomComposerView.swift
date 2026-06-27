import SwiftUI

struct BottomComposerView: View {
    @Binding var draft: String
    @Binding var isEncrypted: Bool

    let canEncrypt: Bool
    let isSaving: Bool
    let onSubmit: () -> Void
    let onExpand: () -> Void

    private var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s3) {
            modeControl

            HStack(alignment: .bottom, spacing: DS.s2) {
                TextField("随便写点什么吧", text: $draft, axis: .vertical)
                    .font(DS.bodyLg())
                    .foregroundColor(DS.textBody)
                    .lineLimit(1...4)
                    .lineSpacing(15 * 0.25)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, DS.s3)
                    .padding(.vertical, DS.s2)
                    .background(DS.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                            .stroke(DS.line, lineWidth: 0.5)
                    )

                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(DS.surfaceSunken)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button(action: onSubmit) {
                    Group {
                        if isSaving {
                            ProgressView()
                                .tint(DS.onPrimary)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .foregroundColor(canSubmit ? DS.onPrimary : DS.textSubtle)
                    .frame(width: 36, height: 36)
                    .background(canSubmit ? DS.primary : DS.surfaceSunken)
                    .clipShape(Circle())
                }
                .disabled(!canSubmit)
                .buttonStyle(.plain)
            }

            if !canEncrypt {
                Text("导入密钥文件后，可将新笔记保存为加密笔记。")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
            }
        }
        .padding(DS.cardPadding)
        .background(DS.surfaceRaised)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DS.line)
                .frame(height: 0.5)
        }
    }

    private var modeControl: some View {
        HStack(spacing: DS.s2) {
            SWTabButton(
                title: "明文",
                systemImage: "doc.text",
                isSelected: !isEncrypted
            ) {
                isEncrypted = false
            }

            SWTabButton(
                title: "加密",
                systemImage: canEncrypt ? "lock.fill" : "lock.slash",
                isSelected: isEncrypted,
                isEnabled: canEncrypt
            ) {
                if canEncrypt { isEncrypted = true }
            }
        }
    }
}
