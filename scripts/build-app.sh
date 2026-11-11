#!/usr/bin/env bash
# Builds dist/LunchBar.app and dist/LunchBar-<version>-macOS.zip from a clean checkout.
#
#   scripts/build-app.sh [--version 2.0.0] [--universal]
#
# --universal builds arm64 + x86_64 (needs full Xcode; the Command Line Tools
# can only build for the host architecture). The app is ad-hoc signed, not
# signed with a Developer ID and not notarized. See README "Gatekeeper".
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

PRODUCT="LunchBar"
BUNDLE_ID="io.github.trevor050.LunchBar"
VERSION="${VERSION:-}"
UNIVERSAL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --universal) UNIVERSAL=1; shift ;;
        *) echo "unknown option: $1" >&2; exit 64 ;;
    esac
done

if [[ -z "${VERSION}" ]]; then
    # A tagged commit builds as that version; anything else is the next release.
    VERSION="$(git describe --tags --exact-match 2>/dev/null | sed 's/^v//' || true)"
    VERSION="${VERSION:-2.0.0}"
fi
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

if [[ "${UNIVERSAL}" == 1 ]]; then
    swift build -c release --product "${PRODUCT}" --arch arm64 --arch x86_64
    BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
    ARCH_LABEL="universal"
else
    swift build -c release --product "${PRODUCT}"
    BIN_DIR="$(swift build -c release --show-bin-path)"
    ARCH_LABEL="$(uname -m)"
fi

APP="dist/${PRODUCT}.app"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_DIR}/${PRODUCT}" "${APP}/Contents/MacOS/${PRODUCT}"
cp Resources/AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${PRODUCT}</string>
    <key>CFBundleExecutable</key>
    <string>${PRODUCT}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${PRODUCT}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License. Not affiliated with Nutrislice.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: required for Apple Silicon and gives the bundle a stable
# identity for notifications and login items. It is NOT a Developer ID signature.
codesign --force --sign - --timestamp=none "${APP}"
codesign --verify --strict "${APP}"

ZIP="dist/${PRODUCT}-${VERSION}-macOS-${ARCH_LABEL}.zip"
rm -f "${ZIP}"
ditto -c -k --norsrc --keepParent "${APP}" "${ZIP}"

echo "Built ${APP} (${VERSION}, ${ARCH_LABEL})"
echo "Archive ${ZIP}"
