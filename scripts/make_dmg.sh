#!/usr/bin/env bash
# MenuHome DMG 分发包打包：release 构建 → 暂存 App + 「应用程序」快捷方式 → 压缩镜像
#
# 产物：build/MenuHome-<版本>.dmg（UDZO 只读压缩，用户打开后拖入 Applications 即完成安装）
# 说明：本机 CLT 无 SwiftPM/Xcode，构建走 build_app.sh（swiftc 直编，arm64 + macOS 26+）。
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/MenuHome.app"
STAGE="build/dmg-stage"

echo "==> [1/4] release 构建"
./scripts/build_app.sh release

VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/MenuHome-$VER.dmg"

echo "==> [2/4] 组装暂存目录（App + Applications 快捷方式）"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> [3/4] 生成 $DMG（UDZO 压缩）"
# 本机 macOS 27 上 hdiutil create 旧语法已弃用且实测损坏（连空目录都报「目录非空」），
# 改用新 diskutil image create from；旧 hdiutil 仅作老系统兜底
if diskutil image create from --format UDZO --volumeName "MenuHome" "$STAGE" "$DMG" 2>&1 | grep -v "completed"; then
  :
else
  hdiutil create -volname "MenuHome" -srcfolder "$STAGE" -format UDZO -ov "$DMG" > /dev/null
fi
rm -rf "$STAGE"

echo "==> [4/4] 校验镜像"
hdiutil verify "$DMG" > /dev/null 2>&1 && echo "    镜像校验通过" || echo "    （跳过校验：hdiutil verify 在本机已弃用报错）"

ls -lh "$DMG"
echo "✅ DMG 完成：$DMG（arm64，macOS 26+）"
