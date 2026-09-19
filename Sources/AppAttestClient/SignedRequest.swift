import Foundation

/// What a server needs on a request to know it is talking to a genuine copy of
/// your app: which key signed it, and the signature over the exact bytes sent.
public struct SignedRequest: Equatable, Sendable {
    public let keyId: String
    public let assertion: String

    public init(keyId: String, assertion: String) {
        self.keyId = keyId
        self.assertion = assertion
    }
}

/// The header names this client sends and `app-attest-gate` reads.
public enum AttestHeader {
    public static let keyId = "x-attest-key-id"
    public static let assertion = "x-attest-assertion"
    public static let transaction = "x-transaction-jws"
}

public enum RequestSigningError: Error, Equatable {
    /// App Attest is unavailable — the simulator, or a device without it.
    case unsupported
    /// The server refused the attestation, or answered something unusable.
    case registrationRejected
    /// The request never reached the server.
    case serverUnreachable
}

/// Signs requests with a per-install key the server has on file.
///
/// The shared secret this replaces was the same string in every copy of an
/// app, readable out of the IPA by anyone. A key that lives in the Secure
/// Enclave has no such copy: the server only ever sees signatures.
public protocol RequestSigning: Sendable {
    /// App Attest is not available on the simulator, and not on every device.
    var isSupported: Bool { get }
    /// Signs `payload`, registering a fresh key with the server first if this
    /// install does not have one yet.
    func sign(_ payload: Data) async throws -> SignedRequest
    /// Forgets the current key. The next `sign` starts over with a new one —
    /// the recovery for when the server no longer recognises ours.
    func reset() async
}
