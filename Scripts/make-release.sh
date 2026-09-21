#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Joël in 't Veld
#
# Builds a release archive that the in-app updater can install.
#
#   ./Scripts/make-release.sh
#
# Produces build/release/ClickLatch.zip and a .sha256 next to it. The version
# comes from Resources/Info.plist, so bump it there first. Upload the zip as an
# asset on a GitHub release whose tag matches that version.
#
# The file name deliberately carries no version. GitHub serves the newest release
# at /releases/latest/download/<asset name>, so a name that never changes gives
# the website one download link that never has to be updated either. The version
# is still in the tag, in the release title and inside the bundle.
#
# The updater refuses anything not signed by the same key as the running copy, so
# build this on a machine that has the signing certificate.
#
# If the build is signed with a Developer ID certificate, the app is also sent to
# Apple for notarisation and the ticket is stapled into the bundle, so it opens
# without any Gatekeeper warning. That needs a stored notarytool profile, once:
#
#   xcrun notarytool store-credentials clicklatch \
#       --apple-id <your Apple ID> --team-id <your team ID> --password <app-specific password>

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ClickLatch"
OUT="$ROOT/build/release"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"

"$ROOT/Scripts/bundle.sh"

APP="$ROOT/build/$APP_NAME.app"
if [[ "$(codesign -dvv "$APP" 2>&1)" == *"Signature=adhoc"* ]]; then
	echo
	echo "WARNING: this build is signed ad hoc. Nobody will be able to install it as an"
	echo "         update, because an ad hoc identity can never match a previous build."
	echo "         Run ./Scripts/create-signing-certificate.sh first."
	echo
fi

# Captured first: piping codesign straight into grep -q makes it die of SIGPIPE,
# which pipefail then reports as a failed pipeline.
SIGNATURE="$(codesign -dvv "$APP" 2>&1)"
if [[ "$SIGNATURE" == *"Authority=Developer ID Application"* ]]; then
	PROFILE="${CLICKLATCH_NOTARY_PROFILE:-clicklatch}"
	echo "==> Notarising (profile '$PROFILE')"
	NOTARY_ZIP="$(mktemp -d)/$APP_NAME.zip"
	ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"
	xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$PROFILE" --wait
	xcrun stapler staple "$APP"
	spctl --assess --type execute --verbose "$APP"
else
	echo
	echo "NOTE: not signed with a Developer ID certificate, so this build cannot be"
	echo "      notarised and downloaders will have to clear the quarantine flag."
	echo
fi

mkdir -p "$OUT"
ZIP="$OUT/$APP_NAME.zip"
rm -f "$ZIP" "$ZIP.sha256"

echo "==> Archiving $APP_NAME $VERSION"
# ditto keeps the signature and extended attributes intact; a plain zip does not.
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | awk '{print $1}' > "$ZIP.sha256"

echo "==> Done"
echo "    $ZIP"
echo "    sha256: $(cat "$ZIP.sha256")"
