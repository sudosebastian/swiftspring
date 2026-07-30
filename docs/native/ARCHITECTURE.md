# Swiftspring Native Architecture

Swiftspring is a fully native Apple mail client for **macOS 14+** and **iOS 17+**.

It replaces the Electron + React UI and the out-of-process C++ `mailsync` engine with:

- **SwiftspringKit** — shared Swift domain layer (models, GRDB, sync actors, auth, search, tasks)
- **SwiftspringUI** — shared SwiftUI screens and platform adapters
- **Apps** — thin macOS / iOS entry points

## Design principles

1. **In-process sync** — one `AccountSyncActor` per account owns IMAP/SMTP sessions.
2. **Tasks drive mutations** — UI queues `MailTask`s; sync applies local then remote changes.
3. **GRDB is the source of truth for UI** — `ValueObservation` / `@Observable` refresh views.
4. **Secrets stay in Keychain** — never persisted in SQLite.
5. **MailCore2 behind a protocol** — IMAP/SMTP/MIME via `MailTransport`; mockable in tests.

## Package layout

```text
Apps/
  SwiftspringMac/
  SwiftspringiOS/
Packages/
  SwiftspringKit/
  SwiftspringUI/
Vendor/          # MailCore2 XCFramework notes
docs/native/
```

## Data flow

```text
SwiftUI → MailService.queue(task)
       → TaskQueue (SQLite)
       → AccountSyncActor
       → MailTransport (MailCore2)
       → GRDB writes
       → ValueObservation → SwiftUI
```

## Electron reference

The legacy Electron tree under `app/` is a **behavior reference** only. Do not port Flux/React code line-by-line. See `MIGRATION.md`.
