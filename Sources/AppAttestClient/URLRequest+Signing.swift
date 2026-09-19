import Foundation

extension URLRequest {
    /// Signs this request's body and applies the headers the server reads.
    ///
    /// ```swift
    /// var request = URLRequest(url: endpoint)
    /// request.httpMethod = "POST"
    /// request.httpBody = try JSONEncoder().encode(payload)
    /// try await request.sign(with: signer, entitlement: storeKitProof)
    /// ```
    ///
    /// Sign **after** setting `httpBody` and never touch it again: the
    /// signature covers those exact bytes, and a single changed byte fails
    /// verification on the server.
    public mutating func sign(
        with signer: some RequestSigning,
        entitlement: (any EntitlementProofProviding)? = nil
    ) async throws {
        let signed = try await signer.sign(httpBody ?? Data())
        setValue(signed.keyId, forHTTPHeaderField: AttestHeader.keyId)
        setValue(signed.assertion, forHTTPHeaderField: AttestHeader.assertion)

        if let jws = await entitlement?.currentTransactionJWS() {
            setValue(jws, forHTTPHeaderField: AttestHeader.transaction)
        }
    }
}
