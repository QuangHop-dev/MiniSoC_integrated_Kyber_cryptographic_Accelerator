param()

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\soc_flow.ps1")

$RepoRoot = Get-SoCRepoRoot -ScriptRoot $PSScriptRoot
$BuildDir = Join-Path $RepoRoot "build\kyber_ext_data_bram_tb"

Initialize-QuestaWork -BuildDir $BuildDir

Push-Location $BuildDir
try {
    & vlog -sv `
        (Join-Path $RepoRoot "rtl\kyber\kyber_ext_data_bram.v") `
        (Join-Path $RepoRoot "tb\tb_kyber_ext_data_bram.sv")
    if ($LASTEXITCODE -ne 0) {
        throw "vlog failed"
    }

    Invoke-SoCQuestaSim -Top "tb_kyber_ext_data_bram" `
        -ExpectedPass "PASS: kyber_ext_data_bram core/wb reads"
}
finally {
    Pop-Location
}
