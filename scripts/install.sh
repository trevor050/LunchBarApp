#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
PRODUCT_NAME="LunchBarApp"
APP_DIR="${PROJECT_ROOT}/dist/${PRODUCT_NAME}.app"
BUNDLE_ID="com.example.LunchBarApp"
TARGET_APPS_DIR="${HOME}/Applications"

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

mkdir -p "${TARGET_APPS_DIR}"
rm -rf "${TARGET_APPS_DIR}/${PRODUCT_NAME}.app"
cp -R "${APP_DIR}" "${TARGET_APPS_DIR}/"

echo "Installed ${PRODUCT_NAME}.app to ${TARGET_APPS_DIR}" \
     "(binary also available in dist/)."
