# Native Swiftspring (Swift)

When working on the native Apple client:

- Source of truth is `Packages/SwiftspringKit` and `Packages/SwiftspringUI`
- Apps live in `Apps/SwiftspringMac` and `Apps/SwiftspringiOS`
- Generate Xcode project with `./scripts/generate-xcode.sh` (requires XcodeGen)
- Electron tree under `app/` is a behavior reference only — do not add new Electron features
- Docs: `docs/native/ARCHITECTURE.md`, `BUILD.md`, `MIGRATION.md`

```bash
xcodegen generate
open Swiftspring.xcodeproj
cd Packages/SwiftspringKit && swift test
```
