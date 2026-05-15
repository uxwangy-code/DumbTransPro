#!/bin/bash
# Create a self-signed code signing identity in a dedicated keychain so
# TCC (Accessibility, etc.) grants persist across rebuilds. Run once.
#
# Uses a separate keychain (~/Library/Keychains/dumbtrans-signing.keychain-db)
# with a known password so codesign never blocks on a SecurityAgent GUI
# prompt — fully automatic.
#
# After this runs, bundle.sh signs with this identity instead of adhoc,
# meaning macOS treats every rebuild as the same app — no need to remove
# and re-add it in System Settings → Privacy → Accessibility.

set -euo pipefail

CERT_NAME="${DUMBTRANS_SIGNING_IDENTITY:-DumbTransPro Dev}"
KEYCHAIN_PATH="${HOME}/Library/Keychains/dumbtrans-signing.keychain-db"
KEYCHAIN_PASS="dumbtrans-local-dev"

if security find-identity -p codesigning "${KEYCHAIN_PATH}" 2>/dev/null | grep -q "\"${CERT_NAME}\""; then
    echo "✓ Code signing identity '${CERT_NAME}' already exists in ${KEYCHAIN_PATH}."
    echo "  bundle.sh will use it automatically."
    exit 0
fi

echo "Creating self-signed code signing identity '${CERT_NAME}'..."

TMP_DIR="$(mktemp -d)"
trap "rm -rf '${TMP_DIR}'" EXIT

KEY_FILE="${TMP_DIR}/key.pem"
CERT_FILE="${TMP_DIR}/cert.pem"
P12_FILE="${TMP_DIR}/cert.p12"
CONFIG_FILE="${TMP_DIR}/openssl.cnf"

cat > "${CONFIG_FILE}" <<EOF
[ req ]
distinguished_name = req_dn
prompt = no
x509_extensions = v3_ext

[ req_dn ]
CN = ${CERT_NAME}

[ v3_ext ]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

# 10-year self-signed cert with codeSigning EKU
openssl req \
    -new -newkey rsa:2048 -nodes -x509 -days 3650 \
    -keyout "${KEY_FILE}" -out "${CERT_FILE}" \
    -config "${CONFIG_FILE}" -extensions v3_ext 2>/dev/null

TMP_P12_PASS="dumbtrans-tmp-$$"
PKCS12_EXPORT_ARGS=(-export)
if openssl pkcs12 -help 2>&1 | grep -q -- "-legacy"; then
    PKCS12_EXPORT_ARGS+=(-legacy)
fi

openssl pkcs12 "${PKCS12_EXPORT_ARGS[@]}" -macalg sha1 \
    -inkey "${KEY_FILE}" -in "${CERT_FILE}" \
    -out "${P12_FILE}" -passout "pass:${TMP_P12_PASS}"

# Create dedicated keychain if missing
if [ ! -f "${KEYCHAIN_PATH}" ]; then
    echo "  → creating dedicated keychain: ${KEYCHAIN_PATH}"
    security create-keychain -p "${KEYCHAIN_PASS}" "${KEYCHAIN_PATH}"
    security set-keychain-settings -lut 86400 "${KEYCHAIN_PATH}"  # 24h auto-lock
fi

# Always unlock before importing / setting partition list
security unlock-keychain -p "${KEYCHAIN_PASS}" "${KEYCHAIN_PATH}"

# Add to user keychain search list (idempotent)
CURRENT_KEYCHAINS=$(security list-keychains -d user | tr -d '\n "')
if ! echo "${CURRENT_KEYCHAINS}" | grep -q "dumbtrans-signing"; then
    echo "  → adding to user keychain search list"
    # Re-list existing keychains then append ours
    EXISTING=$(security list-keychains -d user | sed 's/^ *//' | tr '\n' ' ' | sed 's/"//g')
    security list-keychains -d user -s ${EXISTING} "${KEYCHAIN_PATH}"
fi

# Import private key + cert
security import "${P12_FILE}" \
    -k "${KEYCHAIN_PATH}" \
    -P "${TMP_P12_PASS}" \
    -T /usr/bin/codesign \
    -T /usr/bin/security

# Authorize codesign to use the key WITHOUT GUI prompt
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "${KEYCHAIN_PASS}" "${KEYCHAIN_PATH}" >/dev/null

echo ""
echo "✓ Created identity: ${CERT_NAME}"
echo ""
security find-identity -p codesigning "${KEYCHAIN_PATH}" | grep -E "\"${CERT_NAME}\"" || true
echo ""
echo "Next steps:"
echo "  1. Run ./scripts/bundle.sh — it will sign with '${CERT_NAME}'."
echo "  2. Launch the .app, grant Accessibility once."
echo "  3. Future rebuilds inherit the grant; no need to re-add the app."
