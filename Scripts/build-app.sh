#!/bin/bash
# 构建 .app（无需 Xcode，仅需 Command Line Tools）
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/SelectTranslate"

APP="build/划词翻译.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/SelectTranslate"
cp "Support/Info.plist" "$APP/Contents/Info.plist"

# 优先用固定的本地开发证书签名：重新编译后辅助功能授权不会失效。
# 证书私钥放在独立的空密码钥匙串里（已授权所有程序访问），
# 这样 codesign 不会再弹“允许访问钥匙串”的对话框。
IDENTITY="SelectTranslate Local Dev"
SIGN_KEYCHAIN="$HOME/Library/Keychains/selecttranslate-signing.keychain-db"
if security find-identity -p codesigning "$SIGN_KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
    security unlock-keychain -p "" "$SIGN_KEYCHAIN" 2>/dev/null || true
    codesign --force --deep --sign "$IDENTITY" --keychain "$SIGN_KEYCHAIN" "$APP"
    echo "签名：$IDENTITY"
elif security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --deep --sign "$IDENTITY" "$APP"
    echo "签名：$IDENTITY（登录钥匙串）"
else
    # 没有本地证书时退回 ad-hoc（重新编译后需要重新授权辅助功能）
    codesign --force --deep --sign - "$APP"
    echo "签名：ad-hoc（重新编译后需要重新授权）"
fi

echo ""
echo "构建完成：$APP"
echo "启动：open \"$APP\""