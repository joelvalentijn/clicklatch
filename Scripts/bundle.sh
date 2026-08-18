#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Joël in 't Veld
#
# Builds ClickLocker and wraps the binary in a signed .app bundle.
#
#   ./Scripts/bundle.sh              build and bundle into ./build
#   ./Scripts/bundle.sh --install    also copy the app to /Applications
#   ./Scripts/bundle.sh --run        also launch it (quits a running copy first)
#
# --install is recommended: login items and the Accessibility permission both
# depend on the app staying at one stable path.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ClickLocker"
BUNDLE_ID="com.joelintveld.clicklocker"
APP="$ROOT/build/$APP_NAME.app"
CONFIG="${CONFIG:-release}"

INSTALL=0
RUN=0
for arg in "$@"; do
	case "$arg" in
		--install) INSTALL=1 ;;
		--run) RUN=1 ;;
		*) echo "unknown option: $arg" >&2; exit 2 ;;
	esac
done

cd "$ROOT"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"
BINARY="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad hoc)"
# No developer certificate is assumed, so the signature is ad hoc. The code hash
# changes on every rebuild, which may make macOS ask for the Accessibility
# permission again.
codesign --force --sign - --identifier "$BUNDLE_ID" --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP"

TARGET="$APP"
if [[ $INSTALL -eq 1 ]]; then
	echo "==> Installing to /Applications"
	pkill -x "$APP_NAME" 2>/dev/null || true
	sleep 0.5
	rm -rf "/Applications/$APP_NAME.app"
	cp -R "$APP" "/Applications/$APP_NAME.app"
	TARGET="/Applications/$APP_NAME.app"
fi

echo "==> Done: $TARGET"

if [[ $RUN -eq 1 ]]; then
	echo "==> Launching"
	pkill -x "$APP_NAME" 2>/dev/null || true
	sleep 0.5
	open "$TARGET"
fi
