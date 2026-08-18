#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Joël in 't Veld
#
# Creates a self-signed code signing certificate for ClickLocker.
#
# Why this matters: with an ad hoc signature the app's designated requirement is
# literally the hash of that one binary, so macOS drops the Accessibility
# permission on every rebuild, and the app can never verify an update as coming
# from itself. With a certificate the requirement becomes the identifier plus the
# certificate, which survives rebuilds and updates.
#
#   ./Scripts/create-signing-certificate.sh
#
# One step needs your account password in a system dialog. That part cannot be
# automated, and this script will say so rather than pretend it succeeded.

set -euo pipefail

NAME="${CLICKLOCKER_SIGNING_IDENTITY:-ClickLocker Self-Signed}"
WORK="$(mktemp -d)"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

trap 'rm -rf "$WORK"' EXIT

if security find-identity -v -p codesigning | grep -q "$NAME"; then
	echo "==> '$NAME' already exists; nothing to do."
	security find-identity -v -p codesigning | grep "$NAME"
	exit 0
fi

echo "==> Generating key and certificate"
cat > "$WORK/openssl.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = $NAME

[ ext ]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
	-keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/openssl.cnf" 2>/dev/null

openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
	-out "$WORK/identity.p12" -passout pass: -name "$NAME"

echo "==> Importing into the login keychain"
# -T lets codesign use the key without asking every single time.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "" -T /usr/bin/codesign

echo "==> Marking the certificate as trusted"
echo "    macOS will ask for your account password now. That prompt is the one step"
echo "    that cannot be scripted."
if ! security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"; then
	cat <<EOF

The certificate was imported but NOT trusted, so codesign will refuse to use it.
Either run this script again and confirm the password prompt, or open Keychain
Access, find "$NAME" under login, and set "Code Signing" to "Always Trust".
EOF
	exit 1
fi

echo
echo "==> Done. Available identities:"
security find-identity -v -p codesigning | grep "$NAME" || true
cat <<EOF

Next: run ./Scripts/bundle.sh --install, which now picks this identity up
automatically.

One last time after that, macOS will see ClickLocker as a new program, because
its signature genuinely changed. Remove ClickLocker from Privacy & Security ->
Accessibility with the - button and add it again. From then on the permission
survives rebuilds and updates.
EOF
