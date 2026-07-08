param(
    [string]$Cross = "",
    [string]$Python = "",
    [string]$Make = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\soc_flow.ps1")

$RepoRoot = Get-SoCRepoRoot -ScriptRoot $PSScriptRoot
$Firmware = Build-UartBootloaderFirmware -RepoRoot $RepoRoot -Cross $Cross -Python $Python -Make $Make

Write-Host "UART bootloader ELF: $($Firmware["Elf"])"
Write-Host "UART bootloader BIN: $($Firmware["Bin"])"
Write-Host "UART bootloader HEX: $($Firmware["Hex"])"
Write-Host "UART bootloader IHEX: $($Firmware["IHex"])"
