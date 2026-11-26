# ASUS Zenbook UX3402VA 黑苹果（Hackintosh）安装与修复记录

> macOS 26.7.3 (Tahoe) on ASUS Zenbook 14 OLED UX3402VA — 从"无 GPU 加速、极度卡顿"到"核显满血加速 + 视频硬解"的完整踩坑记录。

本仓库记录了一台 **Raptor Lake-H 笔记本** 安装并调优 macOS 26 Tahoe 的全过程：哪些坑踩过、哪些方案是死路、最后是怎么把 **Intel Iris Xe (0xA7A0) 核显硬件加速** 跑起来的。适合作为同平台（RPL-H/P + Xe 96EU）黑苹果的参考。

---

## 一、机器配置

| 项目 | 规格 |
| --- | --- |
| 机型 | ASUS Zenbook 14 OLED UX3402VA |
| CPU | Intel Core i9-13900H（Raptor Lake-H，14C/20T） |
| 内存 | 32GB LPDDR5 |
| 核显 | Intel Iris Xe Graphics，PCI `8086:0xA7A0` rev04（96EU） |
| 独显 | 无 |
| 无线/蓝牙 | Intel AX211（WiFi `8086:51F1` 正常；蓝牙 `8087:0033` 见下文，未解决） |
| 音频 | Realtek ALC294 + Cirrus CS35L41 |
| 触控板 | `ASUE120C`（I2C HID） |
| 屏幕 | 2560×1600 eDP OLED |
| 存储 | WD SN560 1TB NVMe |
| 系统 | macOS 26.7.3，build 25G342，Darwin 25.6.0 |
| 引导 | OpenCore，SMBIOS MacBookPro16,2，`csr-active-config = 0x803` |
| 双系统 | Windows + macOS |

---

## 二、当前状态

| 组件 | 状态 | 说明 |
| --- | --- | --- |
| **核显加速** | ✅ 已解决 | NootedGreen 驱动栈，VRAM 1536MB / Metal 2 / HiDPI |
| **视频硬解** | ✅ 已解决 | H.264 / HEVC 走 GPU（`-ngreengva` + 打补丁的 VA 插件）；VP9 仍软解 |
| 声卡 | ✅ 已解决 | AppleALC 1.9.8 + SimpleHDA，扬声器/麦克风/内建输出正常 |
| WiFi | ✅ 正常 | 内置 AX211（en0） |
| 亮度 | 🟡 软件调光 | 无原生 PWM，用自研「ASUS 控制台」覆盖层调光 |
| 风扇/性能/键盘背光/充电上限 | ✅ 可用 | MHelper（ASUS WMI）+ 自研 ASUS 控制台 |
| 键盘 | ✅ 基本可用 | 外接键盘 Caps Lock→Control；Win=⌘ / Alt=⌥ / Ctrl=⌃（标准 Mac 布局） |
| **触控板** | ⏳ 修复中 | `ASUE120C` 的 `_CRS` 误用 APIC 中断（IRQ 0x3B>0x2F），需改成 GPIO 中断 |
| **蓝牙** | ❌ 未解决 | Intel AX211 固件停在 v0，软件无解（建议换 BCM/CSR USB 蓝牙棒） |
| **睡眠/唤醒** | ❌ 不可用 | eDP 内屏睡眠后无法重新点亮，只能 `displaysleep`（关屏不睡） |

---

## 三、核心：核显加速是怎么搞定的

### 背景：为什么一开始完全没加速
macOS 26 Tahoe 已删除 `AppleIntelTGLGraphics` 系列 kext，系统里只剩 `AppleGFXHDA`。所以：
- 显卡只能靠兜底驱动 `IONDRVFramebuffer` 占位 → VRAM 15MB、无 Metal、分辨率/刷新率/亮度全锁死、纯 CPU 软件合成（WindowServer 吃掉一个小核），卡到没法用。

### 走过的弯路：WhateverXe 路线（对本机是死路）
社区主流的 `WhateverXe`（b00t0x）通过补丁让系统重新加载 TGL 图形栈。但：
- 本机 `0xA7A0` 在 WhateverXe 里被登记为 `GT::Unknown`，真正实现的只有 `0xA7A8`（64EU）。对应上游 issue **#212 / #104 / #183**，至今 open。
- 试过官方 0.8.5、vikenzo 的 DSC fork（0.8.3-gb3u.3），`WEXEDPDSCAdmitted` 能过但 `N97NativeStartAllowed/Preflight/ReservedGGTT` 全 No → VRAM 仍 15MB。**这条线对 RPL-H 96EU 内屏无解。**

### 成功方案：NootedGreen 驱动栈（路线 B）
参考项目 **`JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe`**（Dell XPS 13 Plus，同为 `8086:A7A0` + Tahoe）。它用的是**另一套栈（NootedGreen）**，不是 WhateverXe：

1. EFI 把 GPU **伪装成 Tiger Lake `device-id 9A49`**（`AAPL,ig-platform-id`、complete-modeset、force-online、`framebuffer-stolenmem` 等）。
2. `NootedGreen.kext`（Lilu 插件）在内存里 patch Apple 的 TGL 驱动。
3. 用户态安装：`AppleIntelTGLGraphics 16.0.2` + `Framebuffer 16.0.0` + HookCase 到 `/Library/Extensions`，Metal 驱动 + `libxedrv` 到 `/Library/GPUBundles`，着色器编译器 `xe.bundle` 到 `/System/Library/Caches`，然后 `kmutil` 重建 AuxKC。
4. 结果：**VRAM 1536MB / Metal 2 / HiDPI 正常，动画流畅。**

### 关键突破：让它在 26.7.3 上也能编译（原本只支持 26.7.1）
原项目锁定 macOS 26.7.1（25G241），其着色器编译器脚本要从**磁盘**读 `libLLVM.dylib`，而 26.7.3 磁盘上已经没有这个文件了。我们发现了两个事实：
- `libLLVM.dylib` 在 26.7.3 **只是进了 dyld 共享缓存**（磁盘无文件，但 `dlopen` 成功、`getVendorSignature` 可解析）。
- Command Line Tools SDK 里自带符号桩 `MacOSX26.5.sdk/.../libLLVM.tbd`（10845 个 llvm 符号）。
- 用该 `.tbd` 替换脚本里"从磁盘生成 tbd"的步骤后，**整套用户态栈在 26.7.3 全部编译成功**。
- 同时确认内核关键补丁 `f2`（`41 54 53 50 F7 C2 ... 74`）在 25G342 的内核缓存里仍存在（命中 3 次），所以补丁能打上。

> 结论：**"只能 26.7.1" 只是因为作者脚本的假设，并非 macOS 26.7.3 的根本限制。**

---

## 四、系统与引导

- 引导：OpenCore；SMBIOS `MacBookPro16,2`；`csr-active-config = 0x803`。
- 日常启动盘：内置 ESP（disk0s1，卷标 SYSTEM）；另有一个 U 盘（`/Volumes/1401`）作为**恢复/维护盘**（其 config 的 boot-args 是安全模式 `-x keepsyms=1`，**故意与内置盘不同**，不要互相同步）。
- 每次改 EFI 都做了整目录备份（见 `docs/` 里的 `EFI-sandbox-*` 记录）。

## 五、配置要点

- **ACPI**：包含 `SSDT-PLUG-ALT`、`SSDT-AWAC`、`SSDT-GPI0`、`SSDT-PNLF`、`SSDT-USBX` 等；另有一条 DSDT 补丁把大量 `PRxx` 处理器对象改名以匹配 MADT。
- **Kernel（kext 顺序）**：Lilu → VirtualSMC → WhateverGreen（可选）→ AppleALC → SimpleHDA → VoodooI2C 系列（VoodooI2CServices/VoodooGPIO/VoodooI2C/VoodooInput/VoodooI2CHID）→ NootedGreen → MHelper → IntelBluetooth 系列。
- **DeviceProperties**（`PciRoot(0x0)/Pci(0x2,0x0)`）：核显伪装成 TGL `9A49`，含 `framebuffer-stolenmem`（stolen memory）。
- **SMBIOS**：本仓库 `config/config-redacted.plist` 里的序列号已脱敏（见该目录 README）。

## 六、关键 boot-args（内置盘）

```
-ngreentglwithgfx -allow3d -disablegfxfirmware ngreen-dmc=adlp -ngreenv189 \
-ngreenkeepefi -ngreenxefix -ngreenfixbootmode amfi_get_out_of_my_way=1 \
ngreenSched=4 ngreenV142=3 ngreenblmax=17777 gfxrst=1 ngreenpm=22 -ngreengva
```

- `-ngreenpm`：CPU 睿频修复（单核/多核提升）。
- `-ngreengva`：开启 H.264/HEVC 硬件解码（会破坏 FairPlay，Apple Music/Apple TV+ 不可用；不需要可去掉）。
- 注意：**Lilu 会把 boot-args 截断在约 228 字符**，所以省掉了仅用于日志的 `IGLogLevel`。

---

## 七、目录结构

```
.
├── README.md                      # 本文件
├── docs/                          # 详细的修复报告与操作手册
│   ├── 修复报告-20261126.md         # 全流程问题清单与结论（最全）
│   ├── 显卡加速-两条路线调研与结论-20261126.md
│   ├── 操作手册-显卡加速修复.md
│   ├── 操作手册-网卡声卡修复.md
│   ├── 黑苹果修复上下文-20261125.md
│   ├── 紧急恢复指南.txt
│   └── ...（其余为各阶段备份/恢复说明）
├── config/
│   ├── config-redacted.plist       # 已脱敏的 OpenCore 配置
│   └── README.md
└── source/
    ├── asus-console/               # 自研 ASUS 控制台（SwiftUI 源码）
    ├── fix-configs/                # 同步 EFI / 装 MHelper / 分辨率 等脚本
    └── touchpad-ssdt/              # 触控板 SSDT 尝试（SSDT-TPD0CRS.dsl/.aml）
```

---

## 八、已知限制与替代方案

- **蓝牙（AX211 `8087:0033`）**：固件停在 v0、`IntelBluetoothOps` 对象未创建，官方明确 Intel 蓝牙"只部分兼容"。已尝试官方 2.4.0 / nightly 2.5.0 × BlueToolFixup 2.7.2 / 2.7.3 全部失败。**推荐直接换 BCM20702 / CSR8510 芯片的 USB 蓝牙棒（免驱）**。
- **睡眠/唤醒**：内屏 eDP 唤醒后无法重新点亮，只能 `pmset -a displaysleep N`（关屏不睡）。
- **原生背光 PWM**：拿不到，用「ASUS 控制台」软件覆盖层调光替代。
- **触控板 `ASUE120C`**：`_CRS` 返回 APIC 中断（IRQ 0x3B，超过 Apple 支持的 0x2F），VoodooI2C 需要 GPIO 中断（`SBFG`）。已在 `source/touchpad-ssdt/` 记录尝试（改 `_CRS` 用 `SBFG` + 轮询模式），尚未验证。
- **Fn 亮度/风扇热键**：Fn+F4/F5/风扇键是 EC/ATKD 层事件，被 `VoodooPS2Keyboard`(BrightnessHack)/ATKD 消费，用户态收不到；替代方案是「ASUS 控制台」滑条与 `⌃⌥↑/↓` 快捷键。

---

## 九、免责与注意

- 本项目仅供学习交流。黑苹果违反 Apple 最终用户许可协议，请自行承担风险。
- 使用 `config/config-redacted.plist` 前**务必**用 GenSMBIOS 生成你自己的序列号（`SystemSerialNumber` / `MLB` / `SystemUUID` / `ROM`），否则无法登录 iCloud / App Store。
- 刷写 EFI 前请先做好整盘备份，并保留一个可启动的 U 盘恢复盘。

## 十、参考

- WhateverXe（RPL 支持现状，issue #212/#104/#183）— `b00t0x/WhateverXe`
- NootedGreen / 用户态 Metal 驱动栈 — `JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe`
- Intel 无线/蓝牙 — `OpenIntelWireless/IntelBluetoothFirmware`（[兼容表](https://openintelwireless.github.io/IntelBluetoothFirmware/Compat.html) / [FAQ](https://openintelwireless.github.io/IntelBluetoothFirmware/FAQ.html)）
- VoodooI2C — `VoodooI2C/VoodooI2C`
- MHelper（macOS 版 G-Helper / ASUS WMI）— `franciumos/MHelper`
