param(
    [switch]$KeepVivadoBuild
)

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptRoot
$RepoFullPath = [System.IO.Path]::GetFullPath($RepoRoot)

function Assert-UnderRepo {
    param([string]$Path)

    $FullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $FullPath.StartsWith($RepoFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove path outside repo: $FullPath"
    }
    return $FullPath
}

$Dirs = @(
    "build",
    "sw\build",
    ".Xil",
    "work",
    "logs",
    "fpga\vivado\.Xil"
)

if (-not $KeepVivadoBuild) {
    $Dirs += "fpga\vivado\build"
}

foreach ($Dir in $Dirs) {
    $Target = Assert-UnderRepo (Join-Path $RepoRoot $Dir)
    if (Test-Path -LiteralPath $Target) {
        Remove-Item -LiteralPath $Target -Recurse -Force
        Write-Host "removed $Dir"
    }
}

$FilePatterns = @(
    "vivado*.log",
    "vivado*.jou",
    "board_kyber_verbose.log",
    "uart_send.log"
)

foreach ($Pattern in $FilePatterns) {
    Get-ChildItem -LiteralPath $RepoRoot -File -Filter $Pattern -ErrorAction SilentlyContinue |
        ForEach-Object {
            $Target = Assert-UnderRepo $_.FullName
            Remove-Item -LiteralPath $Target -Force
            Write-Host "removed $($_.Name)"
        }

    Get-ChildItem -LiteralPath (Join-Path $RepoRoot "fpga\vivado") -File -Filter $Pattern -ErrorAction SilentlyContinue |
        ForEach-Object {
            $Target = Assert-UnderRepo $_.FullName
            Remove-Item -LiteralPath $Target -Force
            Write-Host "removed fpga\vivado\$($_.Name)"
        }
}
