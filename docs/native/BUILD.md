# Building Swiftspring (Native)

## Requirements

- macOS 14+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Generate & open

```bash
xcodegen generate
open Swiftspring.xcodeproj
```

Select the **SwiftspringMac** or **SwiftspringiOS** scheme and Run.

## Packages only

```bash
cd Packages/SwiftspringKit && swift test
cd ../SwiftspringUI && swift build
```

## Demo mode

By default apps bootstrap with `AppEnvironment.bootstrap(demo: true)`, which:

- Uses `InMemoryCredentialStore` (no Keychain prompts in early development)
- Uses a shared `InMemoryMailTransport` seeded with sample messages
- Auto-adds a demo account on first launch

Set `demo: false` and provide OAuth client IDs for real IMAP:

```bash
export SWIFTSPRING_GOOGLE_CLIENT_ID=...
export SWIFTSPRING_MICROSOFT_CLIENT_ID=...
```

## MailCore2

See [Vendor/MailCore2.md](../Vendor/MailCore2.md).
