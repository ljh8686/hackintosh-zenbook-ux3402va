# 明天直接用 —— 触控板 / 麦克风 / 扬声器 预备方案

> 今晚做好的东西都放在这里：`~/Documents/deepseek-harness/明日方案/`
> 目标：你睡醒后照这个清单点几下就能试，不用再等研究。

## 0. 开工前两件事（很重要）
1. **插好「1401」优盘再动 EFI**。现在系统里没插优盘；一旦改坏了要能靠优盘恢复。优盘 EFI 已经和内置一致，能正常引导。
2. 改动都只动 **内置 ESP（disk0s1，卷标 SYSTEM）**；脚本会先自动备份到桌面，再用 `sudo` 提示你输入密码。

## 1. 麦克风（已经装好，只等重启验证）✅
- 我已经把 **IntelSSTDMIC 1.0.3**（Intel SmartSound 数字麦驱动，支持 Alder Lake cAVS2.5≈Raptor Lake）装进 EFI：Kernel 加载顺序 Lilu→AppleALC→SimpleHDA→IntelSSTDMIC；boot-args 追加 `-sstdmiclayout=auto -sstdmicfw=adl -sstdmicforce -sstdmicdbg`。
- **验证方法**：重启后打开「语音备忘录」录一句话 → 有波形/回放有声 = 成功。
- **不行就回退**：双击 `scripts/回退-麦克风恢复config.command`（会还原成今晚改动前的 config，麦克风驱动撤掉，其它不动）。

## 2. 触控板（文件已备好，需要你双击部署 + 冷启动）
- 原理：TPD0(ASUE120C) 的 `_CRS` 里中断用的是 APIC IRQ 59（>47，VoodooI2C 拒绝），要改成走 GPIO(SBFG)。脚本把改好的 DSDT 写进 ESP。
- **先试 T1（低风险）**：`scripts/部署-触控板.command` 选 `1`。只把中断源从 APIC 换成 GPIO，引脚沿用原厂 0，配合已开启的 `-vi2c-force-polling` 很可能就醒。
- **T1 不行再试 T2**：同一脚本选 `2`（GPIO 引脚写成 0xAF，即 GNUM(0x0908000F) 推算值；这版是我用 iasl 重新编译的整表，改动更大、风险稍高）。
- **回退**：`scripts/回退-触控板恢复DSDT.command`（把桌面最新备份的 DSDT 拷回）。
- 改完请**冷关机再开机**（比"重启"更能让 ACPI/GPIO 复位）。

## 3. 扬声器（CS35L41 杜比功放，最难、带风险）
- 情况：硬件能被驱动识别（2×CS35L41、走 SPI、板 1043:16A3），但这台机器**没有 16A3 专属调音数据**；任何出声方案都得借用别的华硕板调音，有**极小概率损伤喇叭**。
- 已准备：CirrusAudioFixup 源码改好并尝试编译（见 `artifacts/` 里是否有 `Cirrus扬声器-CirrusAudioFixup.kext`；若没有则说明今晚没编成功，需要另想办法/继续）。
- **安全的先用**：3.5mm 耳机 / 蓝牙耳机（蓝牙已修好）/ 买个几十块的 USB 声卡——都能让电脑"有外放"，零风险。
- 若仍想冒险试用内置喇叭：只在**低音量**下试，我会给单独的部署+回退脚本（默认仍是只读诊断 `-cirrusro`）。
- ⚠️ 如果你哪天决定试，先保证优盘在手、能回退。

## 4. 文件清单
- `artifacts/DSDT补丁-T1-中断改GPIO.aml`（低风险）
- `artifacts/DSDT补丁-T2-GPIO引脚0xAF.aml`（完整，风险稍高）
- `artifacts/DSDT-原始备份.aml`（原厂 DSDT，最终兜底）
- `artifacts/麦克风-改动前config备份.plist`
- `scripts/部署-触控板.command` / `回退-触控板恢复DSDT.command` / `回退-麦克风恢复config.command`
- `artifacts/Cirrus扬声器-CirrusAudioFixup.kext`（若编成功）

## 5. 一句话建议顺序
先重启验麦克风 → 没声就回退麦克风脚本 → 再插优盘、部署触控板 T1、冷启动 → 好就完事，不好换 T2 / 回退 → 扬声器用耳机/蓝牙或 USB 声卡最省心。

---

## ⚠ 更新（凌晨 2:38，最新，以此为准）
- **扬声器驱动「已经编译成功」**：`artifacts/Cirrus扬声器-CirrusAudioFixup.kext` 就是从源码编好的（已补 1043:16A3 配置、ad-hoc 签名）。上面第 3 节说"若编成功/默认只读"已过时。
- 想试内置喇叭：先**把音量调到 1~2 格**，再双击 `scripts/部署-扬声器.command`（会再弹一次安全确认）→ 冷启动 → 小音量试。异常就 `scripts/回退-扬声器.command`。
- 最省事、零风险的"有外放"仍是：3.5mm 耳机 / 蓝牙耳机（已修好）/ 几十元 USB 声卡。
- 三个东西互相独立，**一次只改一项、各重启一次**最稳。详见同目录 `今早操作顺序.md`。
