#!/bin/sh
set -eu

PROJECT="DeepLink.xcodeproj"
PBXPROJ="$PROJECT/project.pbxproj"

if [ ! -d "$PROJECT" ]; then
    echo "Project validation failed: $PROJECT not found" >&2
    exit 1
fi

# 1. Verify expected targets exist using xcodebuild (no hardcoded UUIDs)
xcodebuild -project "$PROJECT" -list 2>/dev/null | grep -q "DeepSeekBalanceWidgetExtension$" || {
    echo "Project validation failed: target DeepSeekBalanceWidgetExtension not found" >&2
    exit 1
}

# 2. Verify build settings can be resolved for both targets
for target in DeepLink DeepSeekBalanceWidgetExtension; do
    if ! xcodebuild -project "$PROJECT" -target "$target" -showBuildSettings 2>/dev/null >/dev/null; then
        echo "Project validation failed: target $target has invalid build settings" >&2
        exit 1
    fi
done

# 3. Verify bundle identifiers via xcodebuild (no hardcoded UUIDs)
xcodebuild -project "$PROJECT" -target DeepLink -showBuildSettings 2>/dev/null \
    | grep -q "PRODUCT_BUNDLE_IDENTIFIER = com.deepseek.balance" || {
    echo "Project validation failed: app bundle ID not set to com.deepseek.balance" >&2
    exit 1
}

xcodebuild -project "$PROJECT" -target DeepSeekBalanceWidgetExtension -showBuildSettings 2>/dev/null \
    | grep -q "PRODUCT_BUNDLE_IDENTIFIER = com.deepseek.balance.widget" || {
    echo "Project validation failed: widget bundle ID not set to com.deepseek.balance.widget" >&2
    exit 1
}

# 4. Verify entitlements are configured via xcodebuild (no hardcoded UUIDs)
xcodebuild -project "$PROJECT" -target DeepLink -showBuildSettings 2>/dev/null \
    | grep -q "CODE_SIGN_ENTITLEMENTS.*DeepSeekBalance.entitlements" || {
    echo "Project validation failed: app entitlements not configured" >&2
    exit 1
}

xcodebuild -project "$PROJECT" -target DeepSeekBalanceWidgetExtension -showBuildSettings 2>/dev/null \
    | grep -q "CODE_SIGN_ENTITLEMENTS.*DeepSeekBalanceWidget.entitlements" || {
    echo "Project validation failed: widget entitlements not configured" >&2
    exit 1
}

# 5. Verify embed extensions build phase (XcodeGen uses "Embed Foundation Extensions")
grep -q "Embed Foundation Extensions" "$PBXPROJ" || {
    echo "Project validation failed: Embed Foundation Extensions build phase not found in pbxproj" >&2
    exit 1
}

# 6. Verify target dependency on widget exists (no hardcoded UUIDs)
grep -q "PBXTargetDependency" "$PBXPROJ" || {
    echo "Project validation failed: PBXTargetDependency not found in pbxproj" >&2
    exit 1
}

echo "Project validation passed."
