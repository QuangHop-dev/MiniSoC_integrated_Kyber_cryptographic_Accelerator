param(
    [int]$MaxCycles = 2000000,
    [string]$Cross = "",
    [string]$Python = "",
    [string]$Make = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\soc_flow.ps1")

$RepoRoot = Get-SoCRepoRoot -ScriptRoot $PSScriptRoot
$BuildDir = Join-Path $RepoRoot "build\soc_interrupts"
$Firmware = Build-SoCFirmwareApp -RepoRoot $RepoRoot `
    -App "interrupt_smoke" `
    -BuildDirName "interrupt_smoke" `
    -Cross $Cross `
    -Python $Python `
    -Make $Make

New-SoCDirectory -Path $BuildDir
Copy-Item -LiteralPath $Firmware["Hex"] -Destination (Join-Path $BuildDir "firmware.hex") -Force
Initialize-QuestaWork -BuildDir $BuildDir

Push-Location $BuildDir
try {
    $RtlFiles = Get-SoCRtlFiles -RepoRoot $RepoRoot
    & vlog -sv @RtlFiles (Join-Path $RepoRoot "tb\tb_soc_interrupts.sv")
    if ($LASTEXITCODE -ne 0) {
        throw "vlog failed"
    }
    Invoke-SoCQuestaSim -Top "tb_soc_interrupts" `
        -PlusArgs @("+MAX_CYCLES=$MaxCycles") `
        -ExpectedPass "PASS: full microcontroller completed all 8 peripheral and interrupt cases"
}
finally {
    Pop-Location
}
