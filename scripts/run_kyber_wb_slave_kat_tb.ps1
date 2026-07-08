param(
    [int]$Tests = 10000,
    [int]$BatchSize = 100,
    [int]$StartTest = 0,
    [int]$MaxCycles = 20000000,
    [switch]$Resume
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
$BuildDir = Join-Path $RepoRoot "build\kyber_wb_slave_kat_tb"
$VecDir = Join-Path $BuildDir "vectors"
$WorkDir = Join-Path $BuildDir "work"
$LogDir = Join-Path $BuildDir "batch_logs"
$SummaryPath = Join-Path $BuildDir "kat_10000_summary.log"
$GenExe = Join-Path $BuildDir "kyber_kat_vectors.exe"

New-SoCDirectory -Path $BuildDir
New-SoCDirectory -Path $VecDir
New-SoCDirectory -Path $LogDir

if (-not $Resume) {
    Remove-Item -LiteralPath $SummaryPath -Force -ErrorAction SilentlyContinue
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

Remove-SoCDirectorySafe -Path $WorkDir -Root $BuildDir

Push-Location $BuildDir
try {
    & vlib work | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "vlib failed"
    }

    $RtlFiles = Get-KyberRtlFiles -RepoRoot $RepoRoot

    & vlog -sv @RtlFiles (Join-Path $RepoRoot "tb\tb_kyber_wb_slave_kat.sv")
    if ($LASTEXITCODE -ne 0) {
        throw "vlog failed"
    }

    $VecDirPlusarg = $VecDir -replace "\\", "/"
    $Completed = 0
    $RangeEnd = $StartTest + $Tests

    for ($BatchStart = $StartTest; $BatchStart -lt $RangeEnd; $BatchStart += $BatchSize) {
        $BatchCount = [Math]::Min($BatchSize, $RangeEnd - $BatchStart)
        $BatchEnd = $BatchStart + $BatchCount - 1
        $BatchName = "batch_{0:D4}_{1:D5}_{2:D5}.log" -f `
            [int](($BatchStart - $StartTest) / $BatchSize), $BatchStart, $BatchEnd
        $BatchLog = Join-Path $LogDir $BatchName
        $PassMarker = "global range $BatchStart..$BatchEnd"

        if ($Resume -and (Test-Path $BatchLog)) {
            $ExistingLog = Get-Content -LiteralPath $BatchLog -Raw
            if ($ExistingLog -match [regex]::Escape($PassMarker)) {
                Write-Host "SKIP: KAT batch $BatchStart..$BatchEnd already passed"
                $Completed += $BatchCount
                continue
            }
        }

        Write-Host ""
        Write-Host ("=" * 78)
        Write-Host "KAT batch $BatchStart..$BatchEnd ($BatchCount vectors)"
        Write-Host ("=" * 78)

        & $GenExe $VecDir $BatchCount $BatchStart
        if ($LASTEXITCODE -ne 0) {
            throw "Kyber KAT vector generation failed for batch $BatchStart..$BatchEnd"
        }

        Invoke-SoCQuestaSim -Top "tb_kyber_wb_slave_kat" `
            -PlusArgs @(
                "+NUM_TESTS=$BatchCount",
                "+BATCH_START=$BatchStart",
                "+VEC_DIR=$VecDirPlusarg",
                "+MAX_CYCLES=$MaxCycles"
            ) `
            -ExpectedPass $PassMarker

        $CurrentLog = Join-Path $BuildDir "tb_kyber_wb_slave_kat.vsim.log"
        Move-Item -LiteralPath $CurrentLog -Destination $BatchLog -Force
        Add-Content -LiteralPath $SummaryPath `
            -Value ("PASS batch {0}..{1} vectors={2}" -f $BatchStart, $BatchEnd, $BatchCount)
        $Completed += $BatchCount
        Write-Host "PASS: KAT batch $BatchStart..$BatchEnd"
    }

    Add-Content -LiteralPath $SummaryPath `
        -Value ("PASS total range {0}..{1} vectors={2}" -f `
            $StartTest, ($RangeEnd - 1), $Completed)
    Write-Host ""
    Write-Host "PASS: completed $Completed Kyber512 KAT vectors"
    Write-Host "Summary: $SummaryPath"
    Write-Host "Batch logs: $LogDir"
}
finally {
    Pop-Location
}
