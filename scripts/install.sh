#!/usr/bin/env bash
# Builds LunchBar.app and copies it to ~/Applications, then opens it.
# Uninstall: quit LunchBar, then delete ~/Applications/LunchBar.app.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"${PROJECT_ROOT}/scripts/build-app.sh" "$@"

DEST="${HOME}/Applications"
mkdir -p "${DEST}"
pkill -x LunchBar 2>/dev/null || true
rm -rf "${DEST}/LunchBar.app"
cp -R "${PROJECT_ROOT}/dist/LunchBar.app" "${DEST}/"
open "${DEST}/LunchBar.app"
echo "Installed ${DEST}/LunchBar.app"
