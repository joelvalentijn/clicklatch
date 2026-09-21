#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Joël in 't Veld
#
# Builds ClickLatch and wraps the binary in a signed .app bundle.
#
#   ./Scripts/bundle.sh              build and bundle into ./build
#   ./Scripts/bundle.sh --install    also copy the app to /Applications
#   ./Scripts/bundle.sh --run        also launch it (quits a running copy first)
#
# --install is recommended: login items and the Accessibility permission both
# depend on the app staying at one stable path.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ClickLatch"
BUNDLE_ID="com.joelintveld.clicklatch"
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
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Preference order: an Apple-issued Developer ID (the only kind other people's
# Macs accept without a warning), then the self-signed certificate, then ad hoc.
IDENTITY="${CLICKLATCH_SIGNING_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
	IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
		| sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)"
fi
if [[ -z "$IDENTITY" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -q "ClickLatch Self-Signed"; then
	IDENTITY="ClickLatch Self-Signed"
fi

if [[ -n "$IDENTITY" ]]; then
	echo "==> Signing with '$IDENTITY'"
	SIGN_ARGS=(--force --sign "$IDENTITY" --identifier "$BUNDLE_ID")
	if [[ "$IDENTITY" == Developer\ ID\ Application:* ]]; then
		# Notarisation requires the hardened runtime and a secure timestamp.
		SIGN_ARGS+=(--options runtime --timestamp)
	else
		SIGN_ARGS+=(--timestamp=none)
	fi
	codesign "${SIGN_ARGS[@]}" "$APP"
else
	echo "==> Signing ad hoc (no code signing certificate found)"
	echo "    Note: the code hash changes on every rebuild, so macOS will drop the"
	echo "    Accessibility permission each time, and the app cannot update itself."
	echo "    Run ./Scripts/create-signing-certificate.sh to fix that once and for all."
	codesign --force --sign - --identifier "$BUNDLE_ID" --timestamp=none "$APP"
fi
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
