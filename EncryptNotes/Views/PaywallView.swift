import SwiftUI
import StoreKit

struct PaywallView: View {
    @StateObject private var purchaseStore = PurchaseStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "star.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.yellow)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))

                VStack(spacing: 12) {
                    Text("升级 Pro")
                        .font(.title)
                        .fontWeight(.bold)
                        .transition(.move(edge: .top).combined(with: .opacity))

                    Text("解锁无限笔记")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "infinity", text: "无限笔记数量")
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    FeatureRow(icon: "icloud", text: "iCloud 同步")
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    FeatureRow(icon: "key", text: "导出密钥文件")
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    FeatureRow(icon: "trash", text: "重置加密空间")
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                .padding(.horizontal, 40)

                Spacer()

                VStack(spacing: 16) {
                    if purchaseStore.purchaseInProgress {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .transition(.opacity)
                    } else if let product = purchaseStore.products.first {
                        Button {
                            Task {
                                try? await purchaseStore.purchase()
                            }
                        } label: {
                            Text("立即升级 - \(product.displayPrice)")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }

                    Button {
                        Task {
                            await purchaseStore.restorePurchases()
                        }
                    } label: {
                        Text("恢复购买")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            dismiss()
                        }
                    } label: {
                        Text("关闭")
                    }
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)

            Text(text)
                .font(.body)

            Spacer()
        }
    }
}
