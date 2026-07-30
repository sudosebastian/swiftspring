# Migrating from Electron Mailspring

The Electron application under `app/` remains in-tree as a **behavior reference** until the native macOS MVP ships. It is not linked into the Swift apps.

## Mapping

| Legacy | Native |
|--------|--------|
| `Account` model + KeyManager | `Account` + `KeychainCredentialStore` |
| `MailsyncBridge` + child process | `SyncEngine` + `AccountSyncActor` |
| Task JSON over stdin | `MailTask` rows in SQLite |
| `DatabaseStore` read-only | `AppDatabase` / GRDB read-write |
| React thread list | `ThreadListView` |
| Slate composer | `ComposeService` + SwiftUI `TextEditor` |
| iframe body | `HTMLMessageView` (WKWebView + CSP) |

## What not to port

- Flux stores and Reflux
- Electron BrowserWindow / `@electron/remote`
- Plugin `internal_packages` loader
- `edgehill.db` blob schema (native uses a clean GRDB schema)
- Windows / Linux packaging

## Archive plan

After macOS MVP (Phase 4), move `app/`, `playwright/`, Electron root scripts into `archive/electron/` and rewrite the root README around the native client (already started).
