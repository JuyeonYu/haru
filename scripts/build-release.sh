#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SCHEME="ccmaxok"
PROJECT="$PROJECT_ROOT/ccmaxok/ccmaxok.xcodeproj"
BUILD_DIR="$PROJECT_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/haru.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
ZIP_PATH="$BUILD_DIR/haru.zip"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="DUV8UP2WXU" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  -quiet

echo "==> Exporting..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$SCRIPT_DIR/export-options.plist" \
  -quiet

echo "==> Packaging..."
ditto -c -k --keepParent "$EXPORT_PATH/haru.app" "$ZIP_PATH"

SHA256=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')
SIZE=$(stat -f%z "$ZIP_PATH")

echo ""
echo "Build complete!"
echo "  Archive: $ZIP_PATH"
echo "  Size: $((SIZE / 1024 / 1024))MB"
echo "  SHA256: $SHA256"
