#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
cd "$PROJECT_ROOT"

swift build -c release
mkdir -p dist
cp .build/release/LunchBarApp dist/LunchBarApp
( cd dist && zip -r LunchBarApp-macos-arm64.zip LunchBarApp )

echo "Created dist/LunchBarApp-macos-arm64.zip"
