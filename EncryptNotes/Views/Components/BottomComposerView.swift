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
                    .textFieldStyle(.roundedBorder)

                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .accessibilityLabel("展开编辑")

                Button(action: onSubmit) {
                    Group {
                        if isSaving {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up")
                        }
                    }
                }
                .disabled(!canSubmit)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .accessibilityLabel("保存笔记")
            }

            if !canEncrypt {
                Text("在密钥设置中创建或加载密钥后，可将新笔记保存为加密笔记。")
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
        .onChange(of: canEncrypt) { _, newValue in
            if !newValue {
                isEncrypted = false
            }
        }
    }

    private var modeControl: some View {
        Picker("保存方式", selection: $isEncrypted) {
            Label("明文", systemImage: "doc.text")
                .tag(false)

            Label("加密", systemImage: canEncrypt ? "lock.fill" : "lock.slash")
                .tag(true)
                .disabled(!canEncrypt)
        }
        .pickerStyle(.segmented)
        .tint(DS.primary)
        .onChange(of: isEncrypted) { _, newValue in
            if newValue && !canEncrypt {
                isEncrypted = false
            }
        }
    }
}
