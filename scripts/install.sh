#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
PRODUCT_NAME="LunchBarApp"
APP_DIR="${PROJECT_ROOT}/dist/${PRODUCT_NAME}.app"
BUNDLE_ID="com.example.LunchBarApp"
TARGET_APPS_DIR="${HOME}/Applications"
RESOURCES_DIR="${PROJECT_ROOT}/Resources"
ICON_SOURCE="${RESOURCES_DIR}/AppIcon.icns"
CONFIG_SOURCE="${PROJECT_ROOT}/.env"
SUPPORT_DIR="${HOME}/Library/Application Support/LunchBarApp"
CONFIG_DEST="${SUPPORT_DIR}/config.env"
DESKTOP_DIR="${HOME}/Desktop"

mkdir -p "${PROJECT_ROOT}/dist"

module_cache="${PROJECT_ROOT}/.build/ModuleCache.noindex"
export CLANG_MODULE_CACHE_PATH="${module_cache}"
mkdir -p "${module_cache}"
export SWIFTPM_DISABLE_SANDBOX=1
swift build --disable-sandbox -c release

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${PRODUCT_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${PRODUCT_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSBackgroundOnly</key>
    <true/>
</dict>
</plist>
PLIST

cp "${PROJECT_ROOT}/.build/release/${PRODUCT_NAME}" "${APP_DIR}/Contents/MacOS/${PRODUCT_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/${PRODUCT_NAME}"

if [[ -f "${ICON_SOURCE}" ]]; then
    cp "${ICON_SOURCE}" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

mkdir -p "${TARGET_APPS_DIR}"
rm -rf "${TARGET_APPS_DIR}/${PRODUCT_NAME}.app"
cp -R "${APP_DIR}" "${TARGET_APPS_DIR}/"

if [[ -f "${CONFIG_SOURCE}" ]]; then
    mkdir -p "${SUPPORT_DIR}"
    cp "${CONFIG_SOURCE}" "${CONFIG_DEST}"
fi

rm -f "${DESKTOP_DIR}/${PRODUCT_NAME}" \
      "${DESKTOP_DIR}/${PRODUCT_NAME}.app" \
      "${DESKTOP_DIR}/${PRODUCT_NAME}.app alias"

if command -v osascript >/dev/null 2>&1; then
    osascript <<OSA >/dev/null
set targetPath to POSIX file "${TARGET_APPS_DIR}/${PRODUCT_NAME}.app"
set desktopFolder to POSIX file "${DESKTOP_DIR}"
tell application "Finder"
    set aliasName to "${PRODUCT_NAME}"
    set newAlias to make new alias file at desktopFolder to targetPath
    set name of newAlias to aliasName
end tell
OSA
else
    ln -sfn "${TARGET_APPS_DIR}/${PRODUCT_NAME}.app" "${DESKTOP_DIR}/${PRODUCT_NAME}.app"
fi

echo "Installed ${PRODUCT_NAME}.app to ${TARGET_APPS_DIR}" \
     "(binary also available in dist/)."
