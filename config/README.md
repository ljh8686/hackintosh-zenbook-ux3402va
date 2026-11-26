# 配置说明（已脱敏）

`config-redacted.plist` 是本机 OpenCore 的 `config.plist`，用于记录本次安装的关键设置（ACPI 补丁、Kernel 添加的 kext、DeviceProperties 里的核显伪装、NVRAM boot-args 等）。

**已脱敏**：`SystemSerialNumber` / `MLB` / `BoardSerialNumber` 已替换为 `REDACTED-SERIAL`，`SystemUUID` / `SmUUID` 置零，`ROM` 置零字节。

注意：直接用这份配置启动前，**必须**用 OpenCore Configurator / GenSMBIOS 生成你自己的 SMBIOS 序列号（机型 MacBookPro16,2），否则 iCloud/App Store 无法登录、且尽量一人一号避免冲突。

关键设置摘要见根目录 `README.md` 的「配置要点」一节。
