//
//  PurchaseManager.swift
//  SuggestMeSome
//
//  Feature 14 - StoreKit 2 purchase and entitlement management for the
//  one-time Premium Unlock purchase.
//

import Foundation
import Observation

#if canImport(StoreKit)
import StoreKit
#endif

@MainActor
@Observable
final class PurchaseManager {
    static let shared = PurchaseManager()

    private static let entitlementCacheKey = "purchase.entitlement.state.v1"
#if DEBUG
    private static let debugPremiumOverrideKey = "purchase.entitlement.debug.override.v1"
    private static let debugPremiumOverrideStatusMessage = "Developer premium override is active on this debug build."
#endif

    private let userDefaults: UserDefaults
    private let productID: String

#if canImport(StoreKit)
    private var transactionUpdatesTask: Task<Void, Never>?
#endif

    var entitlementState: EntitlementState
    var isLoadingProducts = false
    var isProcessingPurchase = false
    var statusMessage: String?
    var lastErrorMessage: String?

#if canImport(StoreKit)
    var premiumProduct: Product?
#endif

#if DEBUG
    var debugPremiumOverrideEnabled: Bool
#endif

    init(
        userDefaults: UserDefaults = .standard,
        productID: String? = nil,
        startListeningForTransactions: Bool = true
    ) {
        self.userDefaults = userDefaults
        self.productID = productID ?? ComplianceConfiguration.premiumUnlockProductID
#if DEBUG
        self.debugPremiumOverrideEnabled = userDefaults.bool(forKey: Self.debugPremiumOverrideKey)
#endif
        if let rawValue = userDefaults.string(forKey: Self.entitlementCacheKey),
           let cached = EntitlementState(rawValue: rawValue) {
            self.entitlementState = cached
        } else {
            self.entitlementState = .free
        }

#if DEBUG
        if debugPremiumOverrideEnabled {
            self.entitlementState = .premiumUnlocked
            self.statusMessage = Self.debugPremiumOverrideStatusMessage
        }
#endif

#if canImport(StoreKit)
        if startListeningForTransactions {
            transactionUpdatesTask = Task { [weak self] in
                guard let self else { return }
                for await update in Transaction.updates {
                    await self.handleTransactionUpdate(update)
                }
            }
        }
#endif
    }

    var isPremiumUnlocked: Bool {
        entitlementState.hasPremiumAccess
    }

    var premiumDisplayPrice: String {
#if canImport(StoreKit)
        premiumProduct?.displayPrice ?? "$24.99"
#else
        "$24.99"
#endif
    }

    func bootstrap() async {
        await refreshProducts()
        await refreshEntitlements()
    }

    func refreshProducts() async {
#if canImport(StoreKit)
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            premiumProduct = try await Product.products(for: [productID]).first
        } catch {
            lastErrorMessage = "Premium Unlock could not be loaded right now."
        }
#endif
    }

    func refreshEntitlements() async {
#if canImport(StoreKit)
        var hasUnlockedPremium = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == productID else { continue }
            guard transaction.revocationDate == nil else { continue }
            hasUnlockedPremium = true
        }

#if DEBUG
        if debugPremiumOverrideEnabled {
            apply(entitlementState: .premiumUnlocked)
            statusMessage = Self.debugPremiumOverrideStatusMessage
            lastErrorMessage = nil
            return
        }
#endif

        if hasUnlockedPremium {
            apply(entitlementState: .premiumUnlocked)
            statusMessage = "Premium Unlock is active on this device."
        } else {
            apply(entitlementState: .free)
#if DEBUG
            if statusMessage == Self.debugPremiumOverrideStatusMessage {
                statusMessage = nil
            }
#endif
        }
#else
#if DEBUG
        if debugPremiumOverrideEnabled {
            apply(entitlementState: .premiumUnlocked)
            statusMessage = Self.debugPremiumOverrideStatusMessage
            lastErrorMessage = nil
        }
#endif
#endif
    }

    @discardableResult
    func purchasePremiumUnlock() async -> Bool {
        lastErrorMessage = nil
        statusMessage = nil
        isProcessingPurchase = true
        defer { isProcessingPurchase = false }

#if canImport(StoreKit)
        if premiumProduct == nil {
            await refreshProducts()
        }

        guard let premiumProduct else {
            lastErrorMessage = "Premium Unlock is not available right now."
            return false
        }

        do {
            let result = try await premiumProduct.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastErrorMessage = "The purchase could not be verified."
                    return false
                }

                apply(entitlementState: .premiumUnlocked)
                statusMessage = "Premium Unlock is ready to use."
                await transaction.finish()
                return true

            case .pending:
                statusMessage = "Your purchase is pending approval."
                return false

            case .userCancelled:
                statusMessage = "Premium purchase was cancelled."
                return false

            @unknown default:
                lastErrorMessage = "An unknown purchase state was returned."
                return false
            }
        } catch {
            lastErrorMessage = "Premium purchase failed. Please try again."
            return false
        }
#else
        lastErrorMessage = "StoreKit is unavailable on this build."
        return false
#endif
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        lastErrorMessage = nil
        statusMessage = nil
        isProcessingPurchase = true
        defer { isProcessingPurchase = false }

#if canImport(StoreKit)
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if isPremiumUnlocked {
                statusMessage = "Premium Unlock was restored."
                return true
            }
            statusMessage = "No prior Premium Unlock was found for this Apple Account."
            return false
        } catch {
            lastErrorMessage = "Restore Purchases failed. Please try again."
            return false
        }
#else
        lastErrorMessage = "StoreKit is unavailable on this build."
        return false
#endif
    }

    private func apply(entitlementState: EntitlementState) {
        self.entitlementState = entitlementState
        userDefaults.set(entitlementState.rawValue, forKey: Self.entitlementCacheKey)
    }

#if canImport(StoreKit)
    private func handleTransactionUpdate(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else { return }
        guard transaction.productID == productID else { return }

#if DEBUG
        if debugPremiumOverrideEnabled {
            apply(entitlementState: .premiumUnlocked)
            statusMessage = Self.debugPremiumOverrideStatusMessage
            lastErrorMessage = nil
            return
        }
#endif

        if transaction.revocationDate == nil {
            apply(entitlementState: .premiumUnlocked)
            statusMessage = "Premium Unlock is active on this device."
        } else if entitlementState != .premiumUnlocked {
            apply(entitlementState: .free)
        }
    }
#endif

#if DEBUG
    func setDebugPremiumOverride(_ enabled: Bool) {
        debugPremiumOverrideEnabled = enabled
        userDefaults.set(enabled, forKey: Self.debugPremiumOverrideKey)
        lastErrorMessage = nil

        if enabled {
            apply(entitlementState: .premiumUnlocked)
            statusMessage = Self.debugPremiumOverrideStatusMessage
        } else {
            statusMessage = "Developer premium override is off for this debug build."
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refreshEntitlements()
            }
        }
    }
#endif
}
