#!/usr/bin/env bash
# MenuHome 打包脚本：release 构建 → 组装 build/MenuHome.app → ad-hoc 签名
#
# 说明：直接用 swiftc 编译（项目零依赖，无需 SwiftPM）。
# 本机 CommandLineTools 6.4 的 SwiftPM 清单编译器有缺陷（libPackageDescription
# 缺旧签名符号，任何 Package.swift 都无法链接），且 SDK 27 把 @State 宏化而
# CLT 未随附 SwiftUIMacros 插件；仓库源码已手工脱糖 @State，因此 swiftc 直编
# 在 CLT / Xcode 下都能通过。
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-release}"   # release（默认）| debug
BIN=".build/MenuHome"
APP="build/MenuHome.app"

echo "==> [1/3] swiftc 编译（$MODE）"
mkdir -p .build
if [[ "$MODE" == "debug" ]]; then
  xcrun swiftc -swift-version 5 -target arm64-apple-macos13.0 \
    Sources/MenuHome/*.swift -o "$BIN"
else
  xcrun swiftc -swift-version 5 -target arm64-apple-macos13.0 -O \
    Sources/MenuHome/*.swift -o "$BIN"
fi

if [[ ! -f "$BIN" ]]; then
  echo "错误：编译未产出 $BIN" >&2
  exit 1
fi

echo "==> [2/3] 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/MenuHome"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>MenuHome</string>
	<key>CFBundleDisplayName</key>
	<string>MenuHome</string>
	<key>CFBundleIdentifier</key>
	<string>com.menuhome.app</string>
	<key>CFBundleExecutable</key>
	<string>MenuHome</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

echo "==> [3/3] ad-hoc 签名"
codesign --force --sign - "$APP" || true

echo "✅ 构建完成：open build/MenuHome.app"
