#!/usr/bin/env bash
# Code-signs the freshly built DevOrbit.app with a Developer ID identity.
#
# Runs as the fastforge pre-package hook, i.e. after `flutter build macos` and
# before the DMG is assembled. Without MACOS_CERTIFICATE_P12 the script is a
# no-op, so local builds and forks still produce an (ad-hoc signed) DMG.
set -euo pipefail

APP="${BUILD_OUTPUT_FILES%%:*}"
if [[ -z "${APP}" || ! -d "${APP}" ]]; then
  APP="$(ls -d build/macos/Build/Products/Release/*.app | head -1)"
fi
echo "sign_app: target ${APP}"

if [[ -z "${MACOS_CERTIFICATE_P12:-}" ]]; then
  echo "sign_app: MACOS_CERTIFICATE_P12 not set, keeping the ad-hoc signature"
  exit 0
fi

WORK_DIR="${RUNNER_TEMP:-$(mktemp -d)}"
KEYCHAIN="${WORK_DIR}/devorbit-signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
CERT_PATH="${WORK_DIR}/developer-id.p12"

# The secret stores the .p12 base64 encoded on a single line.
printf '%s' "${MACOS_CERTIFICATE_P12}" | openssl base64 -d -A -out "${CERT_PATH}"

security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"
security set-keychain-settings -lut 3600 "${KEYCHAIN}"
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"
security import "${CERT_PATH}" -k "${KEYCHAIN}" \
  -P "${MACOS_CERTIFICATE_PASSWORD:-}" -T /usr/bin/codesign
# Without this the codesign call blocks on a keychain access prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}" >/dev/null
security list-keychains -d user -s "${KEYCHAIN}" \
  $(security list-keychains -d user | tr -d '"')

IDENTITY="${MACOS_SIGN_IDENTITY:-Developer ID Application}"
# --deep keeps the embedded Flutter frameworks and the App Sandbox helpers
# consistent with the outer bundle; --options runtime is required for
# notarization.
codesign --force --deep --options runtime --timestamp \
  --sign "${IDENTITY}" "${APP}"
codesign --verify --deep --strict --verbose=2 "${APP}"

rm -f "${CERT_PATH}"
echo "sign_app: signed with ${IDENTITY}"
