# MailCore2 integration

SwiftspringKit talks to IMAP/SMTP through the `MailTransport` protocol.

## Default (development)

Without MailCore linked, `MailTransportFactory` returns `InMemoryMailTransport` with a seeded demo inbox. This lets the macOS/iOS apps run UI and sync flows offline.

## Production

1. Build [MailCore2](https://github.com/MailCore/mailcore2) for Apple platforms (see upstream `build-mac/README.md`).
2. Produce an XCFramework (or use CocoaPods / SPM mirror) and place it under `Vendor/MailCore.xcframework`.
3. Add the framework to both app targets and to `SwiftspringKit`.
4. Ensure `import MailCore` succeeds so the `#if canImport(MailCore)` branch compiles `MailCoreTransport`.

### Suggested Xcode link flags

- Link `MailCore.xcframework`
- Link system libs as required by MailCore2 (`libz`, `CFNetwork`, `Security`)

### Async wrappers

`MailCoreTransport` wraps block-based `MCOIMAPSession` / `MCOSMTPSession` APIs with `CheckedContinuation` for Swift concurrency.

## OAuth

Gmail and Microsoft need XOAUTH2 tokens. `AccountSyncActor` refreshes tokens via `OAuthService` and passes `accessToken` into the transport.
