#!/bin/bash
# Build ClaudeWatch.app from the single Swift source, without Xcode.
# Produces build/ClaudeWatch.app (ad-hoc signed) which you can `open`.
# (You can also open app/ClaudeWatchApp.swift in an Xcode macOS App target.)
set -euo pipefail
cd "$(dirname "$0")"

APP="ClaudeWatch"
BUNDLE="build/$APP.app"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"

# -parse-as-library is required for the SwiftUI @main App entry point.
swiftc ClaudeWatchApp.swift \
  -o "$BUNDLE/Contents/MacOS/$APP" \
  -parse-as-library \
  -framework SwiftUI -framework AppKit -framework UserNotifications \
  -target arm64-apple-macos14.0

cp Info.plist "$BUNDLE/Contents/Info.plist"

# Ad-hoc signature: enough for a local, personal build (UserNotifications needs
# a signed bundle with a bundle id). For other Macs / no Gatekeeper prompt you
# would sign with your Apple Developer identity instead.
codesign --force --deep --sign - "$BUNDLE"

echo "built: $BUNDLE"
echo "run (menu bar):       open $BUNDLE"
echo "run (with console):   $BUNDLE/Contents/MacOS/$APP"