#!/usr/bin/env bash
# Submits the packaged DMG to Apple's notary service and staples the ticket.
#
# Runs as the fastforge post-package hook. Credentials come from repository
# secrets; when they are absent the DMG is left unnotarized instead of failing
# the build, which keeps forks and local runs working.
set -euo pipefail

OUTPUT_DIR="${OUTPUT_DIRECTORY:-dist}"
DMG="$(ls -t "${OUTPUT_DIR}"/*.dmg 2>/dev/null | head -1 || true)"
if [[ -z "${DMG}" ]]; then
  echo "notarize: no DMG found in ${OUTPUT_DIR}, nothing to submit"
  exit 0
fi
echo "notarize: target ${DMG}"

if [[ -z "${MACOS_NOTARY_APPLE_ID:-}" ||
      -z "${MACOS_NOTARY_PASSWORD:-}" ||
      -z "${MACOS_NOTARY_TEAM_ID:-}" ]]; then
  echo "notarize: credentials not set, skipping"
  exit 0
fi

xcrun notarytool submit "${DMG}" \
  --apple-id "${MACOS_NOTARY_APPLE_ID}" \
  --password "${MACOS_NOTARY_PASSWORD}" \
  --team-id "${MACOS_NOTARY_TEAM_ID}" \
  --wait
# Stapling attaches the ticket so the app opens on a machine that is offline.
xcrun stapler staple "${DMG}"
xcrun stapler validate "${DMG}"
echo "notarize: done"
