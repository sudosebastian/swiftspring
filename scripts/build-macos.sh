#!/usr/bin/env bash
# Build SwiftspringMac as an unsigned Debug .app for local testing (macOS + Xcode required).
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS with Xcode installed." >&2
  echo "This cloud agent is Linux and cannot produce a Mac .app." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing XcodeGen via Homebrew…"
  brew install xcodegen
fi

./scripts/generate-xcode.sh

DERIVED="${DERIVED_DATA_PATH:-build/DerivedData}"
mkdir -p dist "$DERIVED"

echo "Building SwiftspringMac (Debug, unsigned)…"
xcodebuild \
  -project Swiftspring.xcodeproj \
  -scheme SwiftspringMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP=$(find "$DERIVED/Build/Products" -name 'Swiftspring.app' -type d | head -1)
if [[ -z "$APP" ]]; then
  echo "Build succeeded but Swiftspring.app was not found under $DERIVED" >&2
  exit 1
fi

rm -rf dist/Swiftspring.app
ditto "$APP" dist/Swiftspring.app
ditto -c -k --sequesterRsrc --keepParent dist/Swiftspring.app dist/Swiftspring-macOS-debug.zip

echo ""
echo "Done."
echo "  App:  $(pwd)/dist/Swiftspring.app"
echo "  Zip:  $(pwd)/dist/Swiftspring-macOS-debug.zip"
echo ""
echo "Open with:  open dist/Swiftspring.app"
echo "If Gatekeeper blocks it: right-click the app → Open."
