#!/bin/bash
# 只读诊断：GPU / 声卡(CS35L41) / ASUS 控制台 / 相关 kext 状态
echo "===== 系统 ====="; sw_vers; uname -m
echo; echo "===== 显示/显卡 ====="; system_profiler SPDisplaysDataType 2>/dev/null | sed -n '1,40p'
echo; echo "===== 图形/音频 kext ====="
kextstat 2>/dev/null | grep -Ei 'NootedGreen|HookCase|AppleIntelTGL|WhateverXe|AppleALC|SimpleHDA|Cirrus|AppleHDA' || echo "(none)"
echo; echo "===== 系统侧文件 ====="
for p in \
  /Library/Extensions/AppleIntelTGLGraphics.kext \
  /Library/Extensions/AppleIntelTGLGraphicsFramebuffer.kext \
  /Library/Extensions/HookCase.kext \
  /Library/Extensions/CirrusAudioFixup.kext \
  /Library/GPUBundles/AppleIntelTGLGraphicsMTLDriver.bundle \
  /Library/GPUBundles/XeCompilerAdapter.bundle \
  /System/Library/Caches/xe.bundle
do [ -e "$p" ] && echo "OK      $p" || echo "MISSING $p"; done
echo; echo "===== 声卡设备 ====="; system_profiler SPAudioDataType 2>/dev/null | sed -n '1,40p'
echo; echo "===== IOAccelerator ====="; ioreg -rc IOAccelerator 2>/dev/null | grep -E '"VRAM,totalMB"|"IOClass"|MetalPluginName' | head
echo; echo "===== 引导/Boot-args ====="; nvram boot-args 2>/dev/null; nvram csr-active-config 2>/dev/null
echo; echo "===== MHelper / ASUS WMI ====="; kextstat 2>/dev/null | grep -Ei 'mhelper|francium' || echo "(MHelper 未加载)"
echo; echo "===== ASUS控制台 / swiftc ====="; ls -ld "/Applications/ASUS控制台.app" 2>/dev/null || echo "ASUS控制台.app 缺失"; swiftc --version >/dev/null 2>&1 && swiftc --version 2>/dev/null | head -1 || echo "swiftc 不可用 (需 xcode-select --install)"
echo; echo "===== 完成 ====="
