#!/usr/bin/env bash
# MenuHome 应用图标生成：swiftc 编译绘制脚本 → 输出 iconset PNG → iconutil 合成 .icns
# 产物：Assets/AppIcon.icns（已提交入库；build_app.sh 组装时复制进 .app）
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> [1/2] 绘制 iconset（make_icon.swift）"
mkdir -p .build
xcrun swiftc -O -swift-version 5 scripts/make_icon.swift -o .build/make_icon
.build/make_icon

echo "==> [2/2] 合成 Assets/AppIcon.icns"
iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns

ls -lh Assets/AppIcon.icns
echo "✅ 应用图标完成：Assets/AppIcon.icns"
