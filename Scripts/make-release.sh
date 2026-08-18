#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Joël in 't Veld
#
# Builds a release archive that the in-app updater can install.
#
#   ./Scripts/make-release.sh
#
# Produces build/release/ClickLocker-<version>.zip and a .sha256 next to it. The
# version comes from Resources/Info.plist, so bump it there first. Upload the zip
# as an asset on a GitHub release whose tag matches that version.
#
# The updater refuses anything not signed by the same key as the running copy, so
# build this on a machine that has the signing certificate.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ClickLocker"
OUT="$ROOT/build/release"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"

"$ROOT/Scripts/bundle.sh"

APP="$ROOT/build/$APP_NAME.app"
if codesign -dvv "$APP" 2>&1 | grep -q 'Signature=adhoc'; then
	echo
	echo "WARNING: this build is signed ad hoc. Nobody will be able to install it as an"
	echo "         update, because an ad hoc identity can never match a previous build."
	echo "         Run ./Scripts/create-signing-certificate.sh first."
	echo
fi

mkdir -p "$OUT"
ZIP="$OUT/$APP_NAME-$VERSION.zip"
rm -f "$ZIP" "$ZIP.sha256"

echo "==> Archiving $APP_NAME $VERSION"
# ditto keeps the signature and extended attributes intact; a plain zip does not.
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | awk '{print $1}' > "$ZIP.sha256"

echo "==> Done"
echo "    $ZIP"
echo "    sha256: $(cat "$ZIP.sha256")"
