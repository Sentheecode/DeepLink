#!/bin/bash
# Build both targets and install to connected device
# Usage: ./build_and_install.sh [device_id]

set -e

DEVICE="${1:-AC92FA4E-5E6E-5019-B914-0EBE4F75EE8B}"
IDENTITY="849176F0FCF46B87FC33D8470D26C4E13EEBFC52"
PROJECT="DeepLink.xcodeproj"
CONFIG="Debug"

./scripts/validate_project.sh

echo "=== Building App (scheme builds app + widget extension) ==="
xcodebuild -project "$PROJECT" -scheme DeepSeekBalance -configuration "$CONFIG" -destination 'generic/platform=iOS' build

# Find DerivedData and app bundle
DERIVED_DATA=$(xcodebuild -project "$PROJECT" -scheme DeepSeekBalance -showBuildSettings -configuration "$CONFIG" 2>/dev/null | grep -m1 "BUILT_PRODUCTS_DIR" | awk '{print $NF}')
MAIN_APP="$DERIVED_DATA/DeepSeekBalance.app"
WIDGET_APP="$MAIN_APP/PlugIns/DeepSeekBalanceWidgetExtension.appex"

if [ ! -d "$WIDGET_APP" ]; then
  echo "Build failed: Widget Extension was not embedded in $MAIN_APP" >&2
  exit 1
fi

echo "=== Re-signing with correct entitlements ==="
BUILD_DIR=$(dirname "$(dirname "$DERIVED_DATA")")
APP_XCENT=$(find "$BUILD_DIR" -name "DeepSeekBalance.app.xcent" 2>/dev/null | grep "Debug-iphoneos" | grep -v Simulated | head -1)
WIDGET_XCENT=$(find "$BUILD_DIR" -name "DeepSeekBalanceWidgetExtension.appex.xcent" 2>/dev/null | grep "Debug-iphoneos" | grep -v Simulated | head -1)

if [ -f "$WIDGET_XCENT" ]; then
  echo "Re-signing widget: $WIDGET_XCENT"
  xcrun codesign --force --sign "$IDENTITY" --entitlements "$WIDGET_XCENT" "$WIDGET_APP"
fi
if [ -f "$APP_XCENT" ]; then
  echo "Re-signing app: $APP_XCENT"
  xcrun codesign --force --sign "$IDENTITY" --entitlements "$APP_XCENT" "$MAIN_APP"
fi

echo "=== Installing ==="
xcrun devicectl device install app --device "$DEVICE" "$MAIN_APP"

echo "=== Done ==="
