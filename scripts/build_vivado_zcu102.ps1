param(
    [string]$Cross = "",
    [string]$Python = "",
    [string]$Make = "",
    [string]$Vivado = "",
    [string]$OutDir = "",
    [string]$Part = "xczu9eg-ffvb1156-2-e",
    [string]$BoardPart = "xilinx.com:zcu102:part0:3.3",
    [ValidateSet(100, 125, 150, 167, 180, 190, 200)]
    [int]$ClockMHz = 167,
    [int]$Jobs = 4,
    [switch]$CreateOnly,
    [switch]$AllowUnconstrainedIo,
    [switch]$Bootloader
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\soc_flow.ps1")

$RepoRoot = Get-SoCRepoRoot -ScriptRoot $PSScriptRoot
if ($Bootloader) {
    $Firmware = Build-UartBootloaderFirmware -RepoRoot $RepoRoot -Cross $Cross -Python $Python -Make $Make
} else {
    $Firmware = Build-KyberDemoFirmware -RepoRoot $RepoRoot -Cross $Cross -Python $Python -Make $Make
}
$Vivado = Resolve-SoCVivado -Vivado $Vivado

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $RepoRoot "build\vivado\zcu102"
} elseif (-not [System.IO.Path]::IsPathRooted($OutDir)) {
    $OutDir = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $OutDir))
}
New-SoCDirectory -Path $OutDir

$VivadoScriptDir = Join-Path $RepoRoot "fpga\vivado"
$Source = if ($CreateOnly) {
    "create_project.tcl"
} else {
    "build_bitstream.tcl"
}

$PreviousRepoRoot = $env:SOC_REPO_ROOT
$PreviousOutDir = $env:SOC_VIVADO_OUT_DIR
$PreviousFirmware = $env:SOC_FIRMWARE_HEX
$PreviousBootloaderEnable = $env:SOC_BOOTLOADER_ENABLE
$PreviousBootBytes = $env:SOC_BOOT_BYTES
$PreviousBootRomBytes = $env:SOC_BOOT_ROM_BYTES
$PreviousSramBytes = $env:SOC_SRAM_BYTES
$PreviousClockProfile = $env:SOC_CLOCK_PROFILE
$env:SOC_REPO_ROOT = ($RepoRoot -replace "\\", "/")
$env:SOC_VIVADO_OUT_DIR = ($OutDir -replace "\\", "/")
$env:SOC_FIRMWARE_HEX = ($Firmware["Hex"] -replace "\\", "/")
$env:SOC_CLOCK_PROFILE = "$ClockMHz"
if ($Bootloader) {
    $env:SOC_BOOTLOADER_ENABLE = "1"
    $env:SOC_BOOT_BYTES = "32768"
    $env:SOC_BOOT_ROM_BYTES = "16384"
    $env:SOC_SRAM_BYTES = "16384"
} else {
    $env:SOC_BOOTLOADER_ENABLE = "0"
    $env:SOC_BOOT_BYTES = "16384"
    $env:SOC_BOOT_ROM_BYTES = "16384"
    $env:SOC_SRAM_BYTES = "16384"
}

$Args = @(
    "-mode", "batch",
    "-source", $Source,
    "-tclargs",
    "-part", $Part,
    "-board_part", $BoardPart,
    "-clock_profile", "$ClockMHz",
    "-jobs", "$Jobs"
)

if ($AllowUnconstrainedIo) {
    $Args += @("-allow_unconstrained_io", "1")
}

Push-Location $VivadoScriptDir
try {
    Invoke-SoCExternal -FilePath $Vivado -ArgumentList $Args -ErrorMessage "Vivado flow failed"
}
finally {
    Pop-Location
    $env:SOC_REPO_ROOT = $PreviousRepoRoot
    $env:SOC_VIVADO_OUT_DIR = $PreviousOutDir
    $env:SOC_FIRMWARE_HEX = $PreviousFirmware
    $env:SOC_BOOTLOADER_ENABLE = $PreviousBootloaderEnable
    $env:SOC_BOOT_BYTES = $PreviousBootBytes
    $env:SOC_BOOT_ROM_BYTES = $PreviousBootRomBytes
    $env:SOC_SRAM_BYTES = $PreviousSramBytes
    $env:SOC_CLOCK_PROFILE = $PreviousClockProfile
}

Write-Host "Vivado output directory: $OutDir"
Write-Host "SoC clock profile: $ClockMHz MHz"
if ($Bootloader) {
    Write-Host "Bootloader bitstream mode: enabled"
}
