param(
    [int]$KyberRandomTests = 100,
    [int]$KyberKatTests = 100,
    [int]$MaxCycles = 80000000,
    [switch]$SkipKyberUnit
)

$ErrorActionPreference = "Stop"

if (-not $SkipKyberUnit) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run_kyber_ext_data_bram_tb.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "run_kyber_ext_data_bram_tb.ps1 failed"
    }

    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run_kyber_wb_slave_tb.ps1") `
        -Tests $KyberRandomTests `
        -MaxCycles $MaxCycles
    if ($LASTEXITCODE -ne 0) {
        throw "run_kyber_wb_slave_tb.ps1 failed"
    }

    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run_kyber_wb_slave_kat_tb.ps1") `
        -Tests $KyberKatTests `
        -MaxCycles $MaxCycles
    if ($LASTEXITCODE -ne 0) {
        throw "run_kyber_wb_slave_kat_tb.ps1 failed"
    }
}

& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run_soc_interrupt_tb.ps1")
if ($LASTEXITCODE -ne 0) {
    throw "run_soc_interrupt_tb.ps1 failed"
}

& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run_soc_top_kyber_cpu_tb.ps1") `
    -MaxCycles $MaxCycles
if ($LASTEXITCODE -ne 0) {
    throw "run_soc_top_kyber_cpu_tb.ps1 failed"
}

& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run_soc_top_tb.ps1") `
    -MaxCycles $MaxCycles
if ($LASTEXITCODE -ne 0) {
    throw "run_soc_top_tb.ps1 failed"
}

& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run_soc_top_uart_bootloader_tb.ps1")
if ($LASTEXITCODE -ne 0) {
    throw "run_soc_top_uart_bootloader_tb.ps1 failed"
}

Write-Host "PASS: all selected regressions completed"
