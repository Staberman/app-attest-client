# Security

This package signs requests on an authentication path. If you find a
vulnerability in it, please do not open a public issue.

**Report it privately** through GitHub's
[Report a vulnerability](https://github.com/Staberman/app-attest-client/security/advisories/new)
form, or by email to lautaro@staberman.com.ar. Include what you found, how to
reproduce it, and what it lets an attacker do. You will get an answer within a
few days.

## Scope

In scope: anything that lets a request be signed with a key the app did not
generate, makes the client sign a different body from the one it sends, or lets
concurrent calls register more than one key for the same install.

Out of scope: App Attest and the Secure Enclave themselves, which belong to
Apple, and server-side verification, which lives in
[`app-attest-gate`](https://github.com/Staberman/app-attest-gate). Report
issues in the server there.

## Known limits, by design

- **The key id is stored in `UserDefaults`.** It is the fingerprint of the
  public key and your server already knows it, so it is not a secret. The
  private key never leaves the Secure Enclave.
- **App Attest is not available everywhere.** `isSupported` is `false` on the
  simulator and on some devices, and signing then throws
  `RequestSigningError.unsupported`. What your app does in that case, and what
  your server accepts from such devices, is your decision.
