param(
    [string]$Bitstream = "",
    [string]$Vivado = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\soc_flow.ps1")

$RepoRoot = Get-SoCRepoRoot -ScriptRoot $PSScriptRoot
$Vivado = Resolve-SoCVivado -Vivado $Vivado

if ([string]::IsNullOrWhiteSpace($Bitstream)) {
    $Bitstream = Join-Path $RepoRoot "build\vivado\zcu102_bootloader_167mhz\kyber_soc_zcu102.bit"
} elseif (-not [System.IO.Path]::IsPathRooted($Bitstream)) {
    $Bitstream = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Bitstream))
}

if (-not (Test-Path -LiteralPath $Bitstream)) {
    throw "Bitstream not found: $Bitstream"
}

$ProgramScript = Join-Path $RepoRoot "fpga\vivado\program_bitstream.tcl"
$Args = @(
    "-mode", "batch",
    "-source", $ProgramScript,
    "-tclargs", $Bitstream
)

Invoke-SoCExternal -FilePath $Vivado -ArgumentList $Args -ErrorMessage "ZCU102 programming failed"
Write-Host "Programmed ZCU102 bitstream: $Bitstream"
