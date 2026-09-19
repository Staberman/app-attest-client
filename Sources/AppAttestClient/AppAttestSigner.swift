import CryptoKit
import DeviceCheck
import Foundation

/// `DCAppAttestService` plus the two registration calls, as an actor.
///
/// The flow, once per install: ask the server for a challenge, generate a key
/// in the Secure Enclave, attest it against that challenge, and hand the
/// attestation to the server. After that every request is signed with the same
/// key and the server checks the signature and the counter.
@available(iOS 15.0, tvOS 15.0, visionOS 1.0, macOS 12.0, *)
public actor AppAttestSigner: RequestSigning {
    private let baseURL: URL
    private let session: URLSession
    private let defaults: UserDefaults
    private let defaultsKey: String
    private let service = DCAppAttestService.shared

    /// One registration at a time. Two calls racing on a fresh install would
    /// otherwise each register their own key, and the loser's assertion would
    /// be checked against the winner's key — a 401 that looks like a bug in
    /// the crypto and is really a race in the client.
    private var registration: Task<String, Error>?

    /// - Parameters:
    ///   - baseURL: where `challenge` and `register` live, e.g.
    ///     `https://api.example.com/attest`.
    ///   - defaultsKey: where the key id is remembered. The key id is **not**
    ///     a secret — it is the public half's fingerprint and the server has
    ///     it too. The private key never leaves the Secure Enclave.
    public init(
        baseURL: URL,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        defaultsKey: String = "app_attest_key_id"
    ) {
        self.baseURL = baseURL
        self.session = session
        self.defaults = defaults
        self.defaultsKey = defaultsKey
    }

    public nonisolated var isSupported: Bool { DCAppAttestService.shared.isSupported }

    public func sign(_ payload: Data) async throws -> SignedRequest {
        guard isSupported else { throw RequestSigningError.unsupported }

        let keyId = try await registeredKeyId()
        // The server hashes the bytes it received and compares. Sign the body
        // you are actually sending, not a re-encoded copy of it.
        let clientDataHash = Data(SHA256.hash(data: payload))
        let assertion = try await service.generateAssertion(keyId, clientDataHash: clientDataHash)
        return SignedRequest(keyId: keyId, assertion: assertion.base64EncodedString())
    }

    public func reset() {
        registration?.cancel()
        registration = nil
        defaults.removeObject(forKey: defaultsKey)
    }

    // MARK: - Registration

    private func registeredKeyId() async throws -> String {
        if let keyId = defaults.string(forKey: defaultsKey) { return keyId }
        // A registration already under way: wait for it rather than start a second.
        if let inFlight = registration { return try await inFlight.value }

        let task = Task<String, Error> { [self] in
            let keyId = try await register()
            store(keyId)
            return keyId
        }
        registration = task
        defer { registration = nil }
        return try await task.value
    }

    private func store(_ keyId: String) {
        defaults.set(keyId, forKey: defaultsKey)
    }

    /// Challenge → generate key → attest → hand the attestation to the server.
    private func register() async throws -> String {
        let challenge = try await fetchChallenge()
        let keyId = try await service.generateKey()
        let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))
        let attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash)

        var request = URLRequest(url: baseURL.appendingPathComponent("register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RegisterRequest(keyId: keyId, challenge: challenge, attestation: attestation.base64EncodedString())
        )
        request.timeoutInterval = 30

        let (_, response) = try await performOrThrowUnreachable(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RequestSigningError.registrationRejected
        }
        return keyId
    }

    private func fetchChallenge() async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("challenge"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30

        let (data, response) = try await performOrThrowUnreachable(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let body = try? JSONDecoder().decode(ChallengeResponse.self, from: data)
        else {
            throw RequestSigningError.registrationRejected
        }
        return body.challenge
    }

    /// A transport failure is `serverUnreachable`, never `registrationRejected`.
    /// Conflating them turns "you are on a train" into "your device is not
    /// trusted", and the recovery for the two is not the same.
    private func performOrThrowUnreachable(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw RequestSigningError.serverUnreachable
        }
    }

    private struct ChallengeResponse: Decodable {
        let challenge: String
    }

    private struct RegisterRequest: Encodable {
        let keyId: String
        let challenge: String
        let attestation: String
    }
}
