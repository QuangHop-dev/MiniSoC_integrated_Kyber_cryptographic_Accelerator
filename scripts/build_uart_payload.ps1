param(
    [string]$App = "kyber_demo",
    [ValidateSet("imem", "sram")]
    [string]$Target = "imem",
    [string]$Cross = "",
    [string]$Python = "",
    [string]$Make = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\soc_flow.ps1")

$RepoRoot = Get-SoCRepoRoot -ScriptRoot $PSScriptRoot
$Firmware = Build-UartPayloadFirmware -RepoRoot $RepoRoot -App $App -Target $Target -Cross $Cross -Python $Python -Make $Make

Write-Host "UART payload ELF: $($Firmware["Elf"])"
Write-Host "UART payload BIN: $($Firmware["Bin"])"
Write-Host "UART payload HEX: $($Firmware["Hex"])"
Write-Host "UART payload IHEX: $($Firmware["IHex"])"
if ($Target -eq "imem") {
    Write-Host "Default binary destination/entry: 0x00004000"
} else {
    Write-Host "Default binary destination/entry: 0x00010000"
}
