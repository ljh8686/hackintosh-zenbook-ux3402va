#!/bin/bash
# 编译并安装「ASUS 控制台.app」（SwiftUI，来自 ljh8686 仓库最新源码）
# 依赖：Xcode Command Line Tools（swiftc）。若未安装，先运行：xcode-select --install
set -u
BASE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$BASE/asus-console"

if ! swiftc --version >/dev/null 2>&1; then
  echo "未找到 swiftc（需要 Xcode 命令行工具）。"
  echo "请先安装：xcode-select --install   （或在 App Store 安装 Xcode）"
  echo "安装完成后再运行本脚本。"
  exit 2
fi

cd "$SRC" || exit 1
echo "编译 main.swift ..."
swiftc -O -parse-as-library main.swift -o ASUSConsole \
  -framework SwiftUI -framework AppKit -framework IOKit -framework CoreGraphics -framework Combine || {
    echo "编译失败"; exit 1; }

APP="/Applications/ASUS控制台.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ASUSConsole "$APP/Contents/MacOS/ASUSConsole"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>ASUS控制台</string>
<key>CFBundleDisplayName</key><string>ASUS控制台</string>
<key>CFBundleIdentifier</key><string>com.local.asusconsole</string>
<key>CFBundleExecutable</key><string>ASUSConsole</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>en</string></array>
<key>CFBundleAllowMixedLocalizations</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "已构建并安装到 $APP"
echo "依赖 MHelper(org.franciumos.mhelper.driver) 已加载。打开方式：open \"$APP\""
