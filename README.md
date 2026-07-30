# Swiftspring

**Native macOS & iOS mail** — SwiftUI + GRDB + in-process IMAP/SMTP. No Electron. No Chromium.

Swiftspring is a greenfield Apple-platform rewrite of the Mailspring-inspired client formerly in this repository. The legacy Electron app under `app/` remains as a behavior reference only.

## Features (native MVP)

- Shared **SwiftspringKit** for accounts, sync, tasks, search, and compose
- Shared **SwiftspringUI** SwiftUI mailbox (sidebar · threads · conversation)
- Keychain credentials + Google/Microsoft OAuth (`ASWebAuthenticationSession`)
- Generic IMAP/SMTP providers (iCloud, Fastmail, Yahoo, custom, …)
- Demo mailbox transport for offline UI development
- Local FTS5 search, snooze hooks, mail rules, contacts, calendar stubs
- iOS background refresh registration

## Requirements

- macOS 14+ / iOS 17+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Quick start

```bash
brew install xcodegen   # once
xcodegen generate
open Swiftspring.xcodeproj
```

Run the **SwiftspringMac** or **SwiftspringiOS** scheme. First launch adds a demo account with sample mail.

### Real accounts

```bash
export SWIFTSPRING_GOOGLE_CLIENT_ID=your-id.apps.googleusercontent.com
export SWIFTSPRING_MICROSOFT_CLIENT_ID=your-microsoft-app-id
```

Link [MailCore2](Vendor/MailCore2.md) for production IMAP/SMTP.

### Tests

```bash
cd Packages/SwiftspringKit && swift test
```

## Layout

```text
Apps/SwiftspringMac|iOS   App entry points
Packages/SwiftspringKit   Models, GRDB, sync, auth, tasks
Packages/SwiftspringUI    SwiftUI screens
Vendor/                   MailCore2 integration notes
docs/native/              Architecture & migration
app/                      Legacy Electron reference (not used by native apps)
```

## Architecture

See [docs/native/ARCHITECTURE.md](docs/native/ARCHITECTURE.md) and [docs/native/BUILD.md](docs/native/BUILD.md).

```text
SwiftUI → MailTask queue → AccountSyncActor → MailTransport (MailCore2)
                ↓
              GRDB ← ValueObservation ← SwiftUI
```

## License

GPLv3 — see [LICENSE.md](LICENSE.md).
