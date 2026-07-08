param(
    [int]$Tests = 1,
    [int]$MaxCycles = 20000000,
    [string]$Python = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\soc_flow.ps1")

if ($Tests -ne 1) {
    throw "This SoC CPU Kyber test currently runs one KAT case because the boot ROM embeds one vector set"
}

$RepoRoot = Get-SoCRepoRoot -ScriptRoot $PSScriptRoot
$BuildDir = Join-Path $RepoRoot "build\soc_top_kyber_cpu"
$VecDir = Join-Path $BuildDir "vectors"
$WorkDir = Join-Path $BuildDir "work"
$GenExe = Join-Path $BuildDir "kyber_kat_vectors.exe"
$BootHex = Join-Path $VecDir "soc_kyber_cpu_boot.hex"

$Python = Resolve-SoCPython -Python $Python

New-SoCDirectory -Path $BuildDir
New-SoCDirectory -Path $VecDir

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

& $GenExe $VecDir $Tests
if ($LASTEXITCODE -ne 0) {
    throw "Kyber KAT vector generation failed"
}

& $Python (Join-Path $RepoRoot "scripts\gen_soc_kyber_cpu_boot.py") `
    --vectors $VecDir `
    --out $BootHex
if ($LASTEXITCODE -ne 0) {
    throw "SoC Kyber CPU boot ROM generation failed"
}

Remove-SoCDirectorySafe -Path $WorkDir -Root $BuildDir

Push-Location $BuildDir
try {
    & vlib work | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "vlib failed"
    }

    $RtlFiles = Get-SoCRtlFiles -RepoRoot $RepoRoot

    & vlog -sv @RtlFiles (Join-Path $RepoRoot "tb\tb_soc_top_kyber_cpu.sv")
    if ($LASTEXITCODE -ne 0) {
        throw "vlog failed"
    }

    Invoke-SoCQuestaSim -Top "tb_soc_top_kyber_cpu" `
        -PlusArgs @("+MAX_CYCLES=$MaxCycles") `
        -ExpectedPass "PASS: soc_top CPU drove Kyber through Wishbone and matched C KAT reference"
}
finally {
    Pop-Location
}
