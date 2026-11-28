# 修复成果 · 2026-11-28 · 集显(Iris Xe 0xA7A0) Tahoe 26.7.3 硬件加速成功

本目录由 DSH 整理上传，记录 ASUS Zenbook UX3402VA 在 macOS 26.7.3 上把 Intel Iris Xe `8086:A7A0`
真正跑起 **硬件加速（VRAM 1536MB / Metal 2 / HiDPI）** 的最终配方与全过程。

## 实测结果
```
VRAM (Total): 1536 MB
Metal Support: Metal 2
Resolution: 2560 x 1600（UI Looks like: 1280 x 800 @ 60.00Hz，2x HiDPI）
kextstat:
  com.StezzaPilot.NootedGreen 1.0.0
  org.smichaud.HookCase 8.0.1
  com.xxxxx.driver.AppleIntelTGLGraphicsFramebuffer 16.0.0
  com.xxxxx.driver.AppleIntelTGLGraphics 16.0.2
```

## 文件
- `最终成功配方-集显加速-20261128.md` —— **最重要**：最终生效的完整配置 + 三个致命坑 + 回退
- `修复报告.md` —— 全过程（含失败尝试与根治分析）
- `scripts/` —— 一键脚本
  - `restore-gpu.sh` —— 集显修复（官方 NootedGreen le/sle + HookCase + 构建版 MTL/xe.bundle）
  - `一键修复.command` —— 菜单（集显/声卡/ASUS控制台/诊断）
  - `diagnose.sh` —— 只读诊断
  - `build-asus-console.sh` / `install-speaker.sh` / `rollback-speaker.sh`

## 三个致命坑（详见配方文档）
1. 别用 WhateverXe 的 Compat 版 `Framebuffer`——它缺 `AppleIntelBaseController` 全符号，NootedGreen 会 `panic: Failed to route dp symbols`。要用 NootedGreen 官方 `sle_Internal/le` 的原生件。
2. boot-args 别超 228 字符，务必保留 `ngreenblmax=17777`。
3. **MTL 驱动必须带 `libxedrv.dylib`**（构建版），否则 `MTLCompilerService` 报 SIGABRT → 屏幕闪屏进不去桌面。

## 来源
- 正版 le/sle：`github.com/sgiammori/NootedGreen` 的 `sle_Internal/`
- 参考：`JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe`（同 Iris Xe A7A0 + Tahoe，`install-macos.sh`）
- 用户态 26.7.3 构建版（MTL17+libxedrv+xe.bundle）：本机 `路线B-用户态全套-26.7.3构建成功.zip`
