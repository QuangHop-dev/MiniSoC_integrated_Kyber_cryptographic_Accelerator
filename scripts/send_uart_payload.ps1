param(
    [Parameter(Mandatory = $true)]
    [string]$Port,
    [string]$Payload = "",
    [ValidateSet("auto", "bin", "memh", "ihex")]
    [string]$Format = "auto",
    [ValidateSet("imem", "sram")]
    [string]$Target = "imem",
    [uint32]$Dest = 0,
    [uint32]$Entry = 0,
    [int]$Baud = 115200,
    [double]$BannerTimeout = 12.0,
    [string]$Python = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\soc_flow.ps1")

$RepoRoot = Get-SoCRepoRoot -ScriptRoot $PSScriptRoot
$Python = Resolve-SoCPython -Python $Python
Ensure-SoCPythonModule -Python $Python -ModuleName "serial" -PackageName "pyserial"

if ([string]::IsNullOrWhiteSpace($Payload)) {
    $Payload = Join-Path $RepoRoot "sw\build\kyber_demo_uart_$Target\firmware.bin"
}

if ($Dest -eq 0) {
    $Dest = if ($Target -eq "imem") { 0x00004000 } else { 0x00010000 }
}
if ($Entry -eq 0) {
    $Entry = $Dest
}

$Args = @(
    (Join-Path $RepoRoot "sw\tools\uart_loader.py"),
    $Payload,
    "--port", $Port,
    "--baud", "$Baud",
    "--format", $Format,
    "--dest", ("0x{0:x8}" -f $Dest),
    "--entry", ("0x{0:x8}" -f $Entry),
    "--banner-timeout", "$BannerTimeout"
)

Invoke-SoCExternal -FilePath $Python -ArgumentList $Args -ErrorMessage "UART payload send failed"
