param(
    [int]$MaxCycles = 12000000,
    [string]$Cross = "",
    [string]$Python = "",
    [string]$Make = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\soc_flow.ps1")

$RepoRoot = Get-SoCRepoRoot -ScriptRoot $PSScriptRoot
$BuildDir = Join-Path $RepoRoot "build\soc_top_uart_bootloader"

$Bootloader = Build-UartBootloaderFirmware -RepoRoot $RepoRoot -Cross $Cross -Python $Python -Make $Make
$Payload = Build-UartPayloadFirmware -RepoRoot $RepoRoot -App "uart_smoke" -Target "imem" -Cross $Bootloader["Cross"] -Python $Bootloader["Python"] -Make $Bootloader["Make"]

New-SoCDirectory -Path $BuildDir
Copy-Item -LiteralPath $Bootloader["Hex"] -Destination (Join-Path $BuildDir "bootloader.hex") -Force
Copy-Item -LiteralPath $Payload["Hex"] -Destination (Join-Path $BuildDir "payload.hex") -Force
$PayloadBytes = (Get-Item $Payload["Bin"]).Length

Initialize-QuestaWork -BuildDir $BuildDir

Push-Location $BuildDir
try {
    $RtlFiles = Get-SoCRtlFiles -RepoRoot $RepoRoot
    & vlog -sv "+define+SIM_UART_PRINT" @RtlFiles (Join-Path $RepoRoot "tb\tb_soc_top_uart_bootloader.sv")
    if ($LASTEXITCODE -ne 0) {
        throw "vlog failed"
    }

    Invoke-SoCQuestaSim -Top "tb_soc_top_uart_bootloader" `
        -PlusArgs @("+MAX_CYCLES=$MaxCycles", "+PAYLOAD_BYTES=$PayloadBytes") `
        -ExpectedPass "PASS: UART bootloader loaded an IMEM payload and jumped to it"
}
finally {
    Pop-Location
}
