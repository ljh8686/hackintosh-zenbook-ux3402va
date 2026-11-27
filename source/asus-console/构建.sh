#!/bin/bash
# 重新构建 ASUS 控制台.app（需 Xcode CommandLineTools）
cd "$(dirname "$0")"
swiftc -O -parse-as-library main.swift -o ASUSConsole \
  -framework SwiftUI -framework AppKit -framework IOKit -framework CoreGraphics -framework Combine || exit 1
APP="/Applications/ASUS控制台.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ASUSConsole "$APP/Contents/MacOS/ASUSConsole"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null
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
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
codesign --force --deep --sign - "$APP"
echo "已构建到 $APP"
