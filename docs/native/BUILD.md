# Building Swiftspring (Native)

## Requirements

- macOS 14+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Fastest path — build a runnable app

```bash
./scripts/build-macos.sh
open dist/Swiftspring.app
```

If Gatekeeper blocks the unsigned Debug build: right-click the app → **Open**.

## Generate & open in Xcode

```bash
brew install xcodegen   # once
./scripts/generate-xcode.sh
open Swiftspring.xcodeproj
```

Select the **SwiftspringMac** or **SwiftspringiOS** scheme and Run.

## CI artifact

Pushing to this branch runs **Build Native macOS**, which uploads `Swiftspring-macOS-debug.zip` as a workflow artifact (Actions → latest run → Artifacts).

## Packages only

```bash
cd Packages/SwiftspringKit && swift test
cd ../SwiftspringUI && swift build
```

## Demo mode

By default apps bootstrap with `AppEnvironment.bootstrap(demo: true)`, which:

- Uses `InMemoryCredentialStore` (no Keychain prompts in early development)
- Uses a shared `InMemoryMailTransport` seeded with sample messages
- Shows the welcome screen on first launch

Set `demo: false` and provide OAuth client IDs for real IMAP:

```bash
export SWIFTSPRING_GOOGLE_CLIENT_ID=...
export SWIFTSPRING_MICROSOFT_CLIENT_ID=...
```

## MailCore2

See [Vendor/MailCore2.md](../Vendor/MailCore2.md).

## Note on cloud agents

Linux cloud environments cannot produce a Mac `.app` (no Xcode). Use this script on a Mac, or download the CI artifact.
