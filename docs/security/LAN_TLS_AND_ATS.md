# LAN Transport Security, Self-Signed TLS & App Transport Security (ATS)

Luna connects directly from Apple TV on the local network (`_lunacore._tcp` via Bonjour/mDNS or manual server URL) to your self-hosted **LunaCore** server over LAN HTTP (`:8090`) or LAN HTTPS (`:8920`).

## Why `NSAllowsArbitraryLoads` and `allowSelfSignedLanTLS` Default to Enabled

1. **Zero-touch home-cinema onboarding (`NSAllowsArbitraryLoads = true` in `Config/Info.plist`)**:
   - Home-network LunaCore instances typically serve unencrypted HTTP on `:8090` or self-signed HTTPS on `:8920` using mDNS hostnames (`.local`) or arbitrary user-configured LAN URLs that cannot be statically enumerated in `NSExceptionDomains` at compile time.
   - Disabling `NSAllowsArbitraryLoads` would break out-of-the-box Bonjour discovery and direct LAN streaming without manual Xcode/plist reconfiguration.
2. **Self-signed LAN HTTPS (`allowSelfSignedLanTLS = true` default)**:
   - Enables TLS encryption against self-signed or local-CA certificates generated for `.local` and user-configured home servers (`Settings → Avansert → Tillat selvsignert TLS-sertifikat på lokalnett`).

## Defense-in-Depth Built Into Luna

Even with `NSAllowsArbitraryLoads = true` and `allowSelfSignedLanTLS = true`, Luna enforces strict transport and credential boundaries:

- **Host-scoped self-signed TLS trust (`ServerFailoverPolicy.shouldTrustServerHost`)**:
  - `LanURLSessionDelegate` and `EngineTLS.serverTrustEvaluator` accept self-signed certificates **only** when `allowSelfSignedLanTLS == true` **and** the target host matches the currently paired `configuredHost` or ends in `.local`. Public internet hosts and non-paired domains continue to require standard system CA trust.
- **Same-origin credential isolation (`LunaCoreClient.isSameOrigin`)**:
  - `Authorization: Bearer ...` and `X-Device-Id` headers are attached exclusively to requests targeting the paired server's host and expected `:8090` / `:8920` origin, never leaked to external artwork CDNs or third-party hosts.
- **Sideload-safe secret storage & log redaction (`SideloadSafeStorage`, `EngineLog`)**:
  - Device pairing tokens are stored under static Keychain service `"luna.v1.credentials"` (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) and registered with `EngineLog.registerSecret(_:)` so stream URLs and playback logs never expose bearer or stream credentials.

## Threat Model & Limitations

- **Trusted LAN assumption**:
  - Plaintext HTTP (`:8090`) provides no confidentiality or server authentication against an active attacker on the same Wi-Fi/Ethernet segment.
  - `allowSelfSignedLanTLS = true` trusts self-signed certificates for `.local` and `configuredHost` without Trust-On-First-Use (TOFU) certificate pinning. An active on-path attacker inside the local network could intercept `:8920` traffic unless a CA-trusted certificate is used and self-signed fallback is turned off.

## Hardening Recommendations

If your LunaCore reverse proxy uses a publicly trusted or Apple TV-installed CA certificate over HTTPS (`:8920`):

1. Pair Luna using the `https://...` URL.
2. Open **Innstillinger → Avansert** on Apple TV.
3. Disable **Tillat selvsignert TLS-sertifikat på lokalnett** (`allowSelfSignedLanTLS = false`) so Apple TV enforces strict system certificate chain validation on every API, artwork, WebSocket, and media stream connection.
