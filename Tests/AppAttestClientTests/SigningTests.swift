import XCTest
@testable import AppAttestClient

/// `DCAppAttestService` needs real hardware, so the attestation itself is not
/// exercised here. What is: the wire contract — which headers go out, over
/// which bytes, and what happens when there is no entitlement to send.
final class SigningTests: XCTestCase {

    private struct StubSigner: RequestSigning {
        let isSupported = true
        /// The payload the last `sign` was handed, for asserting on.
        let seen = Box()
        func sign(_ payload: Data) async throws -> SignedRequest {
            seen.value = payload
            return SignedRequest(keyId: "key-1", assertion: "sig-1")
        }
        func reset() async {}
    }

    private struct FailingSigner: RequestSigning {
        let isSupported = false
        func sign(_ payload: Data) async throws -> SignedRequest {
            throw RequestSigningError.unsupported
        }
        func reset() async {}
    }

    private struct StubProof: EntitlementProofProviding {
        let jws: String?
        func currentTransactionJWS() async -> String? { jws }
    }

    /// A reference box, so a `Sendable` struct can record what it saw.
    private final class Box: @unchecked Sendable {
        var value: Data?
    }

    func testAppliesKeyIdAndAssertionHeaders() async throws {
        var request = URLRequest(url: URL(string: "https://example.com/x")!)
        request.httpBody = Data("{}".utf8)

        try await request.sign(with: StubSigner())

        XCTAssertEqual(request.value(forHTTPHeaderField: AttestHeader.keyId), "key-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: AttestHeader.assertion), "sig-1")
    }

    func testSignsTheExactBodyBytes() async throws {
        let signer = StubSigner()
        let body = Data("{\"text\":\"hola\"}".utf8)
        var request = URLRequest(url: URL(string: "https://example.com/x")!)
        request.httpBody = body

        try await request.sign(with: signer)

        XCTAssertEqual(signer.seen.value, body)
    }

    func testAnEmptyBodySignsAsEmptyRatherThanCrashing() async throws {
        let signer = StubSigner()
        var request = URLRequest(url: URL(string: "https://example.com/x")!)

        try await request.sign(with: signer)

        XCTAssertEqual(signer.seen.value, Data())
    }

    func testAttachesTheTransactionWhenThereIsOne() async throws {
        var request = URLRequest(url: URL(string: "https://example.com/x")!)
        try await request.sign(with: StubSigner(), entitlement: StubProof(jws: "jws-abc"))
        XCTAssertEqual(request.value(forHTTPHeaderField: AttestHeader.transaction), "jws-abc")
    }

    func testOmitsTheTransactionHeaderWhenNothingIsOwned() async throws {
        var request = URLRequest(url: URL(string: "https://example.com/x")!)
        try await request.sign(with: StubSigner(), entitlement: StubProof(jws: nil))
        XCTAssertNil(request.value(forHTTPHeaderField: AttestHeader.transaction))
    }

    func testOmitsTheTransactionHeaderWhenNoProviderIsGiven() async throws {
        var request = URLRequest(url: URL(string: "https://example.com/x")!)
        try await request.sign(with: StubSigner())
        XCTAssertNil(request.value(forHTTPHeaderField: AttestHeader.transaction))
    }

    func testAFailedSignatureLeavesTheRequestUnsigned() async {
        var request = URLRequest(url: URL(string: "https://example.com/x")!)
        do {
            try await request.sign(with: FailingSigner())
            XCTFail("expected the signer to throw")
        } catch {
            XCTAssertEqual(error as? RequestSigningError, .unsupported)
            XCTAssertNil(request.value(forHTTPHeaderField: AttestHeader.keyId))
        }
    }

    /// These strings are the contract with the server. Changing one silently
    /// breaks every deployed backend, so they are pinned here.
    func testHeaderNamesMatchTheServerContract() {
        XCTAssertEqual(AttestHeader.keyId, "x-attest-key-id")
        XCTAssertEqual(AttestHeader.assertion, "x-attest-assertion")
        XCTAssertEqual(AttestHeader.transaction, "x-transaction-jws")
    }

    func testTransportFailureIsDistinctFromRejection() {
        XCTAssertNotEqual(RequestSigningError.serverUnreachable, RequestSigningError.registrationRejected)
    }
}
