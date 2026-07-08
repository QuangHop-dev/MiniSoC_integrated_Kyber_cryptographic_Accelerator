param(
    [int]$MaxCycles = 80000000,
    [string]$Cross = "",
    [string]$Python = "",
    [string]$Make = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\soc_flow.ps1")

$RepoRoot = Get-SoCRepoRoot -ScriptRoot $PSScriptRoot
$BuildDir = Join-Path $RepoRoot "build\sw_kyber_demo"
$SimFirmwareHex = Join-Path $BuildDir "firmware.hex"

$Firmware = Build-KyberDemoFirmware -RepoRoot $RepoRoot -Cross $Cross -Python $Python -Make $Make
New-SoCDirectory -Path $BuildDir
Copy-Item -LiteralPath $Firmware["Hex"] -Destination $SimFirmwareHex -Force
Initialize-QuestaWork -BuildDir $BuildDir

Push-Location $BuildDir
try {
    $RtlFiles = Get-SoCRtlFiles -RepoRoot $RepoRoot
    & vlog -sv "+define+SIM_UART_PRINT" @RtlFiles (Join-Path $RepoRoot "tb\tb_soc_top_sw_kyber_demo.sv")
    if ($LASTEXITCODE -ne 0) {
        throw "vlog failed"
    }

    Invoke-SoCQuestaSim -Top "tb_soc_top_sw_kyber_demo" `
        -PlusArgs @("+MAX_CYCLES=$MaxCycles") `
        -ExpectedPass "PASS: compiled sw/ kyber_demo firmware ran on soc_top"
}
finally {
    Pop-Location
}
