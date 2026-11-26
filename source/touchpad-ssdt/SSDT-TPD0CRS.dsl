/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20260930 (64-bit version)
 * Copyright (c) 2000 - 2026 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of SSDT-TPD0CRS.aml
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x00000098 (152)
 *     Revision         0x02
 *     Checksum         0x0E
 *     OEM ID           "ASUSHK"
 *     OEM Table ID     "TPD0CRS"
 *     OEM Revision     0x00000000 (0)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20260930 (539363632)
 */
DefinitionBlock ("", "SSDT", 2, "ASUSHK", "TPD0CRS", 0x00000000)
{
    External (_SB_.PC00.I2C0.TPD0, DeviceObj)
    External (_SB_.PC00.I2C0.TPD0.SBFB, BuffObj)
    External (_SB_.PC00.I2C0.TPD0.SBFG, BuffObj)

    Scope (_SB.PC00.I2C0.TPD0)
    {
        Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
        {
            Return (ConcatenateResTemplate (SBFB, SBFG))
        }
    }
}

