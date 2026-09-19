# AppAttestClient

[![CI](https://github.com/Staberman/app-attest-client/actions/workflows/ci.yml/badge.svg)](https://github.com/Staberman/app-attest-client/actions/workflows/ci.yml)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![Platforms](https://img.shields.io/badge/iOS%2015%20%7C%20tvOS%2015%20%7C%20visionOS%201-1B1B1B?style=flat-square)](#requirements)

Sign your app's requests with a Secure Enclave key, so the server can tell a genuine copy of your app from a script with a copied API token.

The client half of **[app-attest-gate](https://github.com/Staberman/app-attest-gate)**. The two agree on the wire format; use either alone if you prefer.

## Installation

```swift
.package(url: "https://github.com/Staberman/app-attest-client.git", from: "1.0.0")
```

## Usage

```swift
import AppAttestClient

let signer = AppAttestSigner(baseURL: URL(string: "https://api.example.com/attest")!)

var request = URLRequest(url: endpoint)
request.httpMethod = "POST"
request.httpBody = try JSONEncoder().encode(payload)

try await request.sign(with: signer)
let (data, response) = try await URLSession.shared.data(for: request)
```

That's it. First call registers a key with your server; every call after that signs the body with it.

**Sign after setting `httpBody`, and do not touch it again.** The signature covers those exact bytes.

### Proving a purchase

```swift
let proof = StoreKitEntitlementProof(productIds: ["app_lifetime"])
try await request.sign(with: signer, entitlement: proof)
```

That attaches the App Store's own signed transaction, which your server verifies against Apple's certificate. The device does not get to *claim* it paid — it forwards Apple's signature and the server decides, which is what lets a free tier live somewhere the user cannot edit.

### When the server stops recognising you

```swift
if response.statusCode == 401 {
    await signer.reset()  // forget the key; the next sign registers a new one
}
```

## What your server has to expose

Two endpoints under the `baseURL` you pass in. Any server can implement them —
[app-attest-gate](https://github.com/Staberman/app-attest-gate) does, but it is
not required.

| | Request | Response |
|---|---|---|
| `POST {baseURL}/challenge` | empty | `{ "challenge": "<string>" }` |
| `POST {baseURL}/register` | `{ "keyId", "challenge", "attestation" }` | any 2xx |

`attestation` is base64. Anything outside 200–299 is read as
`.registrationRejected`.

## What it handles that a first draft usually does not

**Concurrent registration collapses into one.** Two calls racing on a fresh install would each generate and register their own key — and the loser's assertions would then be checked against the winner's key. A 401 that looks like a broken signature and is really a race in the client. `AppAttestSigner` is an actor holding a single in-flight registration `Task`; the second caller awaits the first rather than starting its own.

**"Unreachable" is not "rejected."** A transport failure throws `.serverUnreachable`, never `.registrationRejected`. Conflating them turns *"you are on a train"* into *"your device is not trusted"*, and the recovery for the two is not the same — one is a retry, the other is `reset()`.

**The key id is stored, the key is not.** `UserDefaults` holds the key id, which is the public half's fingerprint and something your server already knows. The private key is generated inside the Secure Enclave and never leaves it, so there is nothing in the binary to extract. Pass `defaultsKey:` to control where it goes.

**Unverified StoreKit transactions are skipped, not forwarded.** Sending one would only earn a rejection after a round trip.

## Headers

| Header | Contents |
|---|---|
| `x-attest-key-id` | which key signed |
| `x-attest-assertion` | base64 assertion over the body's SHA-256 |
| `x-transaction-jws` | the App Store transaction, when there is one |

Pinned in tests, because changing one silently breaks every deployed backend.

## Requirements

iOS 15 · tvOS 15 · visionOS 1 · macOS 12 (builds; App Attest itself is unavailable outside Mac Catalyst).

`isSupported` is `false` on the simulator. Branch on it in development rather than letting every request throw.

## License

MIT
