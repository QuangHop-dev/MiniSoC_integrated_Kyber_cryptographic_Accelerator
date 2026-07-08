param(
    [Parameter(Mandatory = $true)]
    [string]$Port,
    [int]$Tests = 10000,
    [int]$BatchSize = 100,
    [int]$StartTest = 0,
    [int]$Baud = 115200,
    [switch]$Upload,
    [switch]$NoFirmwareBuild,
    [switch]$Resume,
    [string]$Cross = "",
    [string]$Python = "",
    [string]$Make = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\soc_flow.ps1")

if ($Tests -le 0) {
    throw "Tests must be positive"
}
if ($BatchSize -le 0 -or $BatchSize -gt 100) {
    throw "BatchSize must be in range 1..100"
}
if ($StartTest -lt 0 -or ($StartTest + $Tests) -gt 10000) {
    throw "Requested global KAT range must fit within 0..9999"
}

$RepoRoot = Get-SoCRepoRoot -ScriptRoot $PSScriptRoot
$Python = Resolve-SoCPython -Python $Python
Ensure-SoCPythonModule -Python $Python -ModuleName "serial" -PackageName "pyserial"
$BuildDir = Join-Path $RepoRoot "build\kyber_hw_kat_uart"
$VecDir = Join-Path $BuildDir "vectors"
$LogDir = Join-Path $BuildDir "batch_logs"
$SummaryPath = Join-Path $BuildDir "hw_kat_10000_summary.log"
$GenExe = Join-Path $BuildDir "kyber_kat_vectors.exe"

New-SoCDirectory -Path $BuildDir
New-SoCDirectory -Path $VecDir
New-SoCDirectory -Path $LogDir
if (-not $Resume) {
    Remove-Item -LiteralPath $SummaryPath -Force -ErrorAction SilentlyContinue
}

if (-not $NoFirmwareBuild) {
    $Firmware = Build-UartPayloadFirmware -RepoRoot $RepoRoot `
        -App "kyber_hw_kat" `
        -Target "imem" `
        -Cross $Cross `
        -Python $Python `
        -Make $Make

    Write-Host "Firmware BIN: $($Firmware["Bin"])"

    if ($Upload) {
        Write-Host ""
        Write-Host "Press and release CPU_RESET (SW20) when upload waits for bootloader."
        & (Join-Path $PSScriptRoot "send_uart_payload.ps1") `
            -Port $Port `
            -Payload $Firmware["Bin"] `
            -Target imem `
            -Baud $Baud `
            -BannerTimeout 12 `
            -Python $Python
        if ($LASTEXITCODE -ne 0) {
            throw "UART upload failed"
        }
        Start-Sleep -Milliseconds 300
    }
}

$RefDir = Join-Path $RepoRoot "kyber\ref"
$KatDir = Join-Path $RefDir "nistkat"
$RefSources = Get-KyberRefSources -RepoRoot $RepoRoot

& gcc -O2 -DKYBER_K=2 -I $RefDir -I $KatDir `
    (Join-Path $RepoRoot "tb\kyber_kat_vectors.c") `
    @RefSources `
    (Join-Path $KatDir "rng.c") `
    -lcrypto `
    -o $GenExe
if ($LASTEXITCODE -ne 0) {
    throw "gcc failed while building Kyber KAT vector generator"
}

$Completed = 0
$RangeEnd = $StartTest + $Tests
for ($BatchStart = $StartTest; $BatchStart -lt $RangeEnd; $BatchStart += $BatchSize) {
    $BatchCount = [Math]::Min($BatchSize, $RangeEnd - $BatchStart)
    $BatchEnd = $BatchStart + $BatchCount - 1
    $BatchIndex = [int](($BatchStart - $StartTest) / $BatchSize)
    $BatchLog = Join-Path $LogDir ("batch_{0:D4}_{1:D5}_{2:D5}.log" -f $BatchIndex, $BatchStart, $BatchEnd)
    $PassMarker = "global range $BatchStart..$BatchEnd"

    if ($Resume -and (Test-Path $BatchLog)) {
        $ExistingLog = Get-Content -LiteralPath $BatchLog -Raw
        if ($ExistingLog -match [regex]::Escape($PassMarker)) {
            Write-Host "SKIP: hardware KAT batch $BatchStart..$BatchEnd already passed"
            $Completed += $BatchCount
            continue
        }
    }

    Write-Host ""
    Write-Host ("=" * 78)
    Write-Host "Hardware KAT batch $BatchStart..$BatchEnd ($BatchCount vectors)"
    Write-Host ("=" * 78)

    & $GenExe $VecDir $BatchCount $BatchStart
    if ($LASTEXITCODE -ne 0) {
        throw "Kyber KAT vector generation failed for batch $BatchStart..$BatchEnd"
    }

    & $Python (Join-Path $RepoRoot "tools\kyber_hw_kat_uart.py") `
        --port $Port `
        --baud $Baud `
        --vectors $VecDir `
        --start-test $BatchStart `
        --count $BatchCount `
        --log $BatchLog
    if ($LASTEXITCODE -ne 0) {
        throw "Hardware Kyber KAT failed for batch $BatchStart..$BatchEnd"
    }

    Add-Content -LiteralPath $SummaryPath `
        -Value ("PASS batch {0}..{1} vectors={2}" -f $BatchStart, $BatchEnd, $BatchCount)
    $Completed += $BatchCount
    Write-Host "PASS: hardware KAT batch $BatchStart..$BatchEnd"
}

Add-Content -LiteralPath $SummaryPath `
    -Value ("PASS total range {0}..{1} vectors={2}" -f $StartTest, ($RangeEnd - 1), $Completed)
Write-Host ""
Write-Host "PASS: completed $Completed Kyber512 hardware KAT vectors"
Write-Host "Summary: $SummaryPath"
Write-Host "Batch logs: $LogDir"
