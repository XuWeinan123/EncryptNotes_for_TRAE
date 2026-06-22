import SwiftUI
import StoreKit

struct PaywallView: View {
    @StateObject private var purchaseStore = PurchaseStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.s8) {
                    VStack(spacing: DS.s3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 56, weight: .regular))
                            .foregroundColor(DS.pro)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))

                        VStack(spacing: DS.s2) {
                            Text("升级 PRO")
                                .font(DS.display())
                                .foregroundColor(DS.textEmphasize)
                                .transition(.move(edge: .top).combined(with: .opacity))

                            Text("解锁无限笔记")
                                .font(DS.bodyLg())
                                .foregroundColor(DS.textSecondary)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(.top, DS.s6)

                    VStack(alignment: .leading, spacing: DS.s4) {
                        FeatureRow(icon: "infinity", text: "无限笔记数量")
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        FeatureRow(icon: "icloud", text: "iCloud 同步")
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        FeatureRow(icon: "key", text: "导出密钥文件")
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        FeatureRow(icon: "trash", text: "重置加密空间")
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    .padding(DS.cardPadding)
                    .dsCardSurface()
                    .padding(.horizontal, DS.s6)

                    VStack(spacing: DS.s4) {
                        if purchaseStore.purchaseInProgress {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .transition(.opacity)
                        } else if let product = purchaseStore.products.first {
                            Button {
                                Task {
                                    do {
                                        try await purchaseStore.purchase()
                                    } catch {
                                        errorMessage = error.localizedDescription
                                        showError = true
                                    }
                                }
                            } label: {
                                Text("立即升级 - \(product.displayPrice)")
                                    .font(DS.body())
                                    .foregroundColor(DS.onPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(DS.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }

                        Button {
                            Task {
                                await purchaseStore.restorePurchases()
                            }
                        } label: {
                            Text("恢复购买")
                                .font(DS.body())
                                .foregroundColor(DS.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                    .padding(.horizontal, DS.s6)
                    .padding(.bottom, DS.s8)
                }
                .frame(maxWidth: .infinity)
            }
            .background(DS.bg.ignoresSafeArea())
            .toolbarBackground(DS.surfaceRaised, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .alert("购买失败", isPresented: $showError) {
                Button("确定") {}
            } message: {
                Text(errorMessage)
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: DS.s4) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(DS.pro)
                .frame(width: 28)

            Text(text)
                .font(DS.bodyLg())
                .foregroundColor(DS.textBody)

            Spacer()
        }
    }
}
