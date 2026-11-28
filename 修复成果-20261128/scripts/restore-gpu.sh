#!/bin/bash
# 集显修复（官方 NootedGreen 正确做法，已在本机验证 kmutil create 成功）
# 关键：用 NootedGreen 官方 sle_Internal/le 的原生 Apple 驱动(带 AppleIntelBaseController 全符号) + HookCase，
#       不用 WhateverXe 的 Compat（那版缺符号会 panic: Failed to route dp symbols）。
set -u
if [ "$(id -u)" -ne 0 ]; then exec sudo /bin/bash "$0" "$@"; fi
BASE="$(cd "$(dirname "$0")/.." && pwd)"
LE="$BASE/payload-official/le"; SLE="$BASE/payload-official/sle"; HC="$BASE/payload/LibraryExtensions/HookCase.kext"
STAMP="$(date +%Y%m%d-%H%M%S)"; BK="/Users/Shared/NootedGreen-official-$STAMP"; mkdir -p "$BK/LibraryExtensions" "$BK/GPUBundles"
say(){ printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
for d in "$LE/AppleIntelTGLGraphics.kext" "$LE/AppleIntelTGLGraphicsFramebuffer.kext" "$HC"; do [ -e "$d" ] || { echo "缺少 $d"; exit 1; }; done

say "1/7 备份"; for k in AppleIntelTGLGraphics AppleIntelTGLGraphicsFramebuffer HookCase AppleIntelTGLCompat; do [ -e /Library/Extensions/$k.kext ] && cp -R /Library/Extensions/$k.kext "$BK/LibraryExtensions/"; done; cp -R /Library/GPUBundles/. "$BK/GPUBundles/" 2>/dev/null
say "2/7 装 le kexts"; for k in AppleIntelTGLGraphics AppleIntelTGLGraphicsFramebuffer; do rm -rf "/Library/Extensions/$k.kext"; cp -R "$LE/$k.kext" "/Library/Extensions/$k.kext"; done
say "3/7 Graphics Gen7 匹配 + 版本"; K=/Library/Extensions/AppleIntelTGLGraphics.kext/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :IOKitPersonalities:Gen7:IOPCIPrimaryMatch 0x9a498086" "$K" 2>/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 16.0.2" "$K" 2>/dev/null
say "4/7 HookCase"; rm -rf /Library/Extensions/HookCase.kext; cp -R "$HC" /Library/Extensions/HookCase.kext
say "5/7 sle bundles"; for b in AppleIntelTGLGraphicsMTLDriver AppleIntelTGLGraphicsGLDriver AppleIntelTGLGraphicsVADriver AppleIntelTGLGraphicsVAME AppleIntelGraphicsShared; do [ -d "$SLE/$b.bundle" ] && rm -rf "/Library/Extensions/$b.bundle" && cp -R "$SLE/$b.bundle" "/Library/Extensions/$b.bundle"; done
[ -d "$BASE/payload/GPUBundles/AppleIntelTGLGraphicsMTLDriver.bundle" ] && rm -rf /Library/GPUBundles/AppleIntelTGLGraphicsMTLDriver.bundle && cp -R "$BASE/payload/GPUBundles/AppleIntelTGLGraphicsMTLDriver.bundle" /Library/GPUBundles/
[ -d "$SLE/AppleIntelGraphicsShared.bundle" ] && rm -rf /Library/GPUBundles/AppleIntelGraphicsShared.bundle && cp -R "$SLE/AppleIntelGraphicsShared.bundle" /Library/GPUBundles/
rm -rf /Library/Extensions/AppleIntelTGLCompat.kext
say "6/7 重签名 + 权限"; for k in AppleIntelTGLGraphics AppleIntelTGLGraphicsFramebuffer; do /usr/bin/codesign --force --sign - "/Library/Extensions/$k.kext" >/dev/null 2>&1; done
chown -R root:wheel /Library/Extensions /Library/GPUBundles; chmod -R u+rwX,go+rX /Library/Extensions /Library/GPUBundles
say "7/7 重建 AuxKC（无 -x）"
kmutil create -n aux -z -V release -r /Library/Extensions --allow-missing-kdk \
  -B /System/Library/KernelCollections/BootKernelExtensions.kc \
  -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
  -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc --no-authentication \
  && echo "AuxKC 成功" || { echo "!! AuxKC 失败"; exit 1; }
kmutil load -z --load-style match-only || true
echo "完成，请重启。成功标志：VRAM 1536MB / Metal 2。"
