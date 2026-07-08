param(
    [string]$Cross = "",
    [string]$Python = "",
    [string]$Make = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\soc_flow.ps1")

$RepoRoot = Get-SoCRepoRoot -ScriptRoot $PSScriptRoot
$Firmware = Build-KyberDemoFirmware -RepoRoot $RepoRoot -Cross $Cross -Python $Python -Make $Make

Write-Host "Firmware ELF: $($Firmware["Elf"])"
Write-Host "Firmware BIN: $($Firmware["Bin"])"
Write-Host "Firmware HEX: $($Firmware["Hex"])"
