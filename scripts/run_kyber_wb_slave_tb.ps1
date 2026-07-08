param(
    [int]$Tests = 100,
    [UInt64]$Seed = 1311768467463790320,
    [int]$MaxCycles = 20000000
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\soc_flow.ps1")

$RepoRoot = Get-SoCRepoRoot -ScriptRoot $PSScriptRoot
$BuildDir = Join-Path $RepoRoot "build\kyber_wb_slave_tb"
$VecDir = Join-Path $BuildDir "vectors"
$WorkDir = Join-Path $BuildDir "work"
$GenExe = Join-Path $BuildDir "kyber_ref_vectors.exe"

New-SoCDirectory -Path $BuildDir
New-SoCDirectory -Path $VecDir

$RefDir = Join-Path $RepoRoot "kyber\ref"
$RefSources = Get-KyberRefSources -RepoRoot $RepoRoot

& gcc -O2 -Wall -Wextra -DKYBER_K=2 -I $RefDir `
    (Join-Path $RepoRoot "tb\kyber_ref_vectors.c") `
    @RefSources `
    -o $GenExe

if ($LASTEXITCODE -ne 0) {
    throw "gcc failed while building Kyber C reference vector generator"
}

& $GenExe $VecDir $Tests $Seed
if ($LASTEXITCODE -ne 0) {
    throw "Kyber C reference vector generation failed"
}

Remove-SoCDirectorySafe -Path $WorkDir -Root $BuildDir

Push-Location $BuildDir
try {
    & vlib work | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "vlib failed"
    }

    $RtlFiles = Get-KyberRtlFiles -RepoRoot $RepoRoot

    & vlog -sv @RtlFiles (Join-Path $RepoRoot "tb\tb_kyber_wb_slave.sv")
    if ($LASTEXITCODE -ne 0) {
        throw "vlog failed"
    }

    $VecDirPlusarg = $VecDir -replace "\\", "/"
    Invoke-SoCQuestaSim -Top "tb_kyber_wb_slave" `
        -PlusArgs @("+NUM_TESTS=$Tests", "+VEC_DIR=$VecDirPlusarg", "+MAX_CYCLES=$MaxCycles") `
        -ExpectedPass "PASS: kyber_wb_slave matched C reference"
}
finally {
    Pop-Location
}
