param(
    [string]$Python = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\soc_flow.ps1")

$RepoRoot = Get-SoCRepoRoot -ScriptRoot $PSScriptRoot
$Python = Resolve-SoCPython -Python $Python
Ensure-SoCPythonModule -Python $Python -ModuleName "serial" -PackageName "pyserial"
$Gui = Join-Path $RepoRoot "tools\firmware_gui.py"

& $Python $Gui
if ($LASTEXITCODE -ne 0) {
    throw "Firmware GUI exited with code $LASTEXITCODE"
}
