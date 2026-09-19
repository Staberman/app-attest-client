import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

/// Something that can prove a purchase to the server: the App Store's own
/// signed transaction, which the server verifies against Apple's certificate.
///
/// The device does not get to *claim* it paid — it forwards Apple's signature
/// and the server decides. That is what lets a free tier live somewhere the
/// user cannot edit.
public protocol EntitlementProofProviding: Sendable {
    func currentTransactionJWS() async -> String?
}

#if canImport(StoreKit)
/// The current entitlement as StoreKit 2 reports it, in JWS form.
///
/// Picks the newest verified transaction among `productIds`. Unverified
/// transactions are skipped rather than forwarded: sending one would only make
/// the server reject the request after a round trip.
@available(iOS 15.0, tvOS 15.0, visionOS 1.0, macOS 12.0, *)
public struct StoreKitEntitlementProof: EntitlementProofProviding {
    private let productIds: Set<String>

    public init(productIds: some Sequence<String>) {
        self.productIds = Set(productIds)
    }

    public func currentTransactionJWS() async -> String? {
        var newest: (date: Date, jws: String)?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard productIds.isEmpty || productIds.contains(transaction.productID) else { continue }

            // `jwsRepresentation` is what the server verifies; the decoded
            // transaction is only for choosing between them here.
            let candidate = (date: transaction.purchaseDate, jws: result.jwsRepresentation)
            if newest == nil || candidate.date > newest!.date {
                newest = candidate
            }
        }

        return newest?.jws
    }
}
#endif
