import Foundation
import StoreKit

@MainActor
final class PurchaseStore: ObservableObject {
    static let shared = PurchaseStore()

    @Published private(set) var isPro: Bool = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseInProgress: Bool = false
    @Published var errorMessage: String?

    private let proProductId = "pro_lifetime"
    private var updateListenerTask: Task<Void, Error>?

    private init() {
        updateListenerTask = listenForTransactions()
        Task {
            await loadProducts()
            await checkPurchasedProducts()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    func loadProducts() async {
        do {
            let productIds = [proProductId]
            products = try await Product.products(for: productIds)
        } catch {
            errorMessage = "Failed to load products"
        }
    }

    func purchase() async throws {
        guard let product = products.first(where: { $0.id == proProductId }) else {
            throw PurchaseError.productNotFound
        }

        purchaseInProgress = true
        defer { purchaseInProgress = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            isPro = true
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await checkPurchasedProducts()
        } catch {
            errorMessage = "Failed to restore purchases"
        }
    }

    private func checkPurchasedProducts() async {
        var hasPro = false

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == proProductId {
                    hasPro = true
                    break
                }
            }
        }

        isPro = hasPro
    }

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.checkPurchasedProducts()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw PurchaseError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }
}

enum PurchaseError: Error, LocalizedError {
    case productNotFound
    case verificationFailed
    case purchaseFailed

    var errorDescription: String? {
        switch self {
        case .productNotFound: return "Product not found"
        case .verificationFailed: return "Purchase verification failed"
        case .purchaseFailed: return "Purchase failed"
        }
    }
}
