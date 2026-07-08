Set-StrictMode -Version 2.0

function Get-SoCRepoRoot {
    param([string]$ScriptRoot)
    return (Resolve-Path (Join-Path $ScriptRoot "..")).Path
}

function Resolve-SoCPython {
    param([string]$Python = "")

    if (-not [string]::IsNullOrWhiteSpace($Python)) {
        return $Python
    }

    $BundledPython = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
    if (Test-Path $BundledPython) {
        return $BundledPython
    }

    $PythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($PythonCmd) {
        return $PythonCmd.Source
    }

    throw "Cannot find Python. Pass -Python C:\path\to\python.exe"
}

function Ensure-SoCPythonModule {
    param(
        [string]$Python,
        [string]$ModuleName,
        [string]$PackageName = ""
    )

    if ([string]::IsNullOrWhiteSpace($PackageName)) {
        $PackageName = $ModuleName
    }

    $CheckCode = "import importlib.util, sys; sys.exit(0 if importlib.util.find_spec('$ModuleName') else 1)"
    & $Python -c $CheckCode *> $null
    if ($LASTEXITCODE -eq 0) {
        return
    }

    Write-Host "Python module '$ModuleName' is missing. Installing package '$PackageName' for:"
    Write-Host "  $Python"
    Invoke-SoCExternal -FilePath $Python `
        -ArgumentList @("-m", "pip", "install", $PackageName) `
        -ErrorMessage "Failed to install Python package '$PackageName'"

    & $Python -c $CheckCode *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Python module '$ModuleName' is still unavailable after installing '$PackageName'"
    }
}

function Resolve-SoCMake {
    param([string]$Make = "")

    if (-not [string]::IsNullOrWhiteSpace($Make)) {
        return $Make
    }

    $MakeCmd = Get-Command mingw32-make -ErrorAction SilentlyContinue
    if (-not $MakeCmd) {
        $MakeCmd = Get-Command make -ErrorAction SilentlyContinue
    }
    if ($MakeCmd) {
        return $MakeCmd.Source
    }

    throw "Cannot find mingw32-make or make"
}

function Resolve-SoCRiscvCross {
    param([string]$Cross = "")

    if (-not [string]::IsNullOrWhiteSpace($Cross)) {
        return $Cross
    }

    $Toolchain = Get-Command riscv64-unknown-elf-gcc -ErrorAction SilentlyContinue
    if ($Toolchain) {
        return ($Toolchain.Source -replace "gcc\.exe$", "")
    }

    if (Test-Path "C:\SysGCC\risc-v\bin\riscv64-unknown-elf-gcc.exe") {
        return "C:/SysGCC/risc-v/bin/riscv64-unknown-elf-"
    }

    throw "Cannot find riscv64-unknown-elf-gcc. Pass -Cross C:/path/to/riscv64-unknown-elf-"
}

function Resolve-SoCVivado {
    param([string]$Vivado = "")

    if (-not [string]::IsNullOrWhiteSpace($Vivado)) {
        return $Vivado
    }

    $VivadoCmd = Get-Command vivado -ErrorAction SilentlyContinue
    if ($VivadoCmd) {
        return $VivadoCmd.Source
    }

    $KnownVivado = "C:\Vivado_Enterprise\Vivado\2021.2\bin\vivado.bat"
    if (Test-Path $KnownVivado) {
        return $KnownVivado
    }

    throw "Cannot find Vivado. Pass -Vivado C:\path\to\vivado.bat"
}

function Invoke-SoCExternal {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$ErrorMessage
    )

    $PreviousErrorActionPreference = $ErrorActionPreference
    try {
        # Windows PowerShell wraps native stderr as NativeCommandError when
        # ErrorActionPreference is Stop. Capture it without truncating the
        # underlying tool's diagnostic output.
        $ErrorActionPreference = "Continue"
        $Output = & $FilePath @ArgumentList 2>&1
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }
    foreach ($Line in $Output) {
        Write-Host $Line.ToString()
    }
    if ($ExitCode -ne 0) {
        throw $ErrorMessage
    }
}

function New-SoCDirectory {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Remove-SoCDirectorySafe {
    param(
        [string]$Path,
        [string]$Root
    )

    if (-not (Test-Path $Path)) {
        return
    }

    $ResolvedRoot = (Resolve-Path $Root).Path
    $ResolvedPath = (Resolve-Path $Path).Path
    if (-not $ResolvedPath.StartsWith($ResolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove directory outside root: $ResolvedPath"
    }

    Remove-Item -LiteralPath $ResolvedPath -Recurse -Force
}

function Get-KyberRefSources {
    param([string]$RepoRoot)

    $RefDir = Join-Path $RepoRoot "kyber\ref"
    return @(
        "kem.c",
        "indcpa.c",
        "polyvec.c",
        "poly.c",
        "ntt.c",
        "cbd.c",
        "reduce.c",
        "verify.c",
        "fips202.c",
        "symmetric-shake.c"
    ) | ForEach-Object { Join-Path $RefDir $_ }
}

function Get-KyberRtlFiles {
    param([string]$RepoRoot)

    return Get-ChildItem (Join-Path $RepoRoot "rtl\kyber") -Filter *.v |
        Sort-Object Name |
        ForEach-Object { $_.FullName }
}

function Get-SoCRtlFiles {
    param([string]$RepoRoot)

    $Files = @()
    $Files += Get-ChildItem (Join-Path $RepoRoot "rtl\cpu") -Filter *.v |
        Sort-Object Name |
        ForEach-Object { $_.FullName }
    $Files += @(
        (Join-Path $RepoRoot "rtl\mem\boot_rom_wb.v"),
        (Join-Path $RepoRoot "rtl\mem\bootloader_mem_wb.v"),
        (Join-Path $RepoRoot "rtl\mem\imem_wb.v"),
        (Join-Path $RepoRoot "rtl\mem\sram_wb.v"),
        (Join-Path $RepoRoot "rtl\periph\gpio_wb.v"),
        (Join-Path $RepoRoot "rtl\periph\i2c_wb.v"),
        (Join-Path $RepoRoot "rtl\periph\pic_wb.v"),
        (Join-Path $RepoRoot "rtl\periph\timer_wb.v"),
        (Join-Path $RepoRoot "rtl\periph\uart_wb.v"),
        (Join-Path $RepoRoot "rtl\bus\wb_interconnect.v")
    )
    $Files += Get-KyberRtlFiles -RepoRoot $RepoRoot
    $Files += (Join-Path $RepoRoot "rtl\soc_top.v")
    return $Files
}

function Build-SoCFirmwareApp {
    param(
        [string]$RepoRoot,
        [string]$App,
        [string]$BuildDirName,
        [string]$Linker = "linker.ld",
        [string]$Cross = "",
        [string]$Python = "",
        [string]$Make = "",
        [int]$MaxBinBytes = 0
    )

    $Cross = Resolve-SoCRiscvCross -Cross $Cross
    $Python = Resolve-SoCPython -Python $Python
    $Make = Resolve-SoCMake -Make $Make
    $SwDir = Join-Path $RepoRoot "sw"

    Push-Location $SwDir
    try {
        $PythonForMake = "`"$Python`""
        Invoke-SoCExternal -FilePath $Make -ArgumentList @(
            "APP=$App",
            "BUILD_DIR=build/$BuildDirName",
            "LINKER=$Linker",
            "CROSS=$Cross",
            "PYTHON=$PythonForMake"
        ) -ErrorMessage "$App firmware build failed"
    }
    finally {
        Pop-Location
    }

    $OutDir = Join-Path $SwDir "build\$BuildDirName"
    $FirmwareHex = Join-Path $OutDir "firmware.hex"
    $FirmwareBin = Join-Path $OutDir "firmware.bin"
    $FirmwareElf = Join-Path $OutDir "firmware.elf"
    $FirmwareIHex = Join-Path $OutDir "firmware.ihex"
    if (-not (Test-Path $FirmwareHex)) {
        throw "Missing firmware hex: $FirmwareHex"
    }
    if (($MaxBinBytes -gt 0) -and ((Get-Item $FirmwareBin).Length -gt $MaxBinBytes)) {
        throw "$App binary exceeds limit: $((Get-Item $FirmwareBin).Length) bytes > $MaxBinBytes"
    }

    return ,@{
        Hex = $FirmwareHex
        Bin = $FirmwareBin
        Elf = $FirmwareElf
        IHex = $FirmwareIHex
        Cross = $Cross
        Python = $Python
        Make = $Make
    }
}

function Build-UartBootloaderFirmware {
    param(
        [string]$RepoRoot,
        [string]$Cross = "",
        [string]$Python = "",
        [string]$Make = ""
    )

    return Build-SoCFirmwareApp -RepoRoot $RepoRoot `
        -App "uart_bootloader" `
        -BuildDirName "uart_bootloader" `
        -Linker "linker.ld" `
        -Cross $Cross `
        -Python $Python `
        -Make $Make `
        -MaxBinBytes 0x4000
}

function Build-UartPayloadFirmware {
    param(
        [string]$RepoRoot,
        [string]$App = "kyber_demo",
        [ValidateSet("imem", "sram")]
        [string]$Target = "imem",
        [string]$Cross = "",
        [string]$Python = "",
        [string]$Make = ""
    )

    $BuildName = "${App}_uart_${Target}"
    $Linker = if ($Target -eq "imem") { "linker_upload_imem.ld" } else { "linker_upload_sram.ld" }

    return Build-SoCFirmwareApp -RepoRoot $RepoRoot `
        -App $App `
        -BuildDirName $BuildName `
        -Linker $Linker `
        -Cross $Cross `
        -Python $Python `
        -Make $Make `
        -MaxBinBytes 0x4000
}

function Build-KyberDemoFirmware {
    param(
        [string]$RepoRoot,
        [string]$Cross = "",
        [string]$Python = "",
        [string]$Make = ""
    )

    $Cross = Resolve-SoCRiscvCross -Cross $Cross
    $Python = Resolve-SoCPython -Python $Python
    $Make = Resolve-SoCMake -Make $Make
    $SwDir = Join-Path $RepoRoot "sw"

    Push-Location $SwDir
    try {
        $PythonForMake = "`"$Python`""
        Invoke-SoCExternal -FilePath $Make -ArgumentList @("clean", "APP=kyber_demo", "CROSS=$Cross", "PYTHON=$PythonForMake") -ErrorMessage "firmware clean failed"
        Invoke-SoCExternal -FilePath $Make -ArgumentList @("APP=kyber_demo", "CROSS=$Cross", "PYTHON=$PythonForMake") -ErrorMessage "firmware build failed"
    }
    finally {
        Pop-Location
    }

    $FirmwareHex = Join-Path $SwDir "build\kyber_demo\firmware.hex"
    $FirmwareBin = Join-Path $SwDir "build\kyber_demo\firmware.bin"
    $FirmwareElf = Join-Path $SwDir "build\kyber_demo\firmware.elf"
    if (-not (Test-Path $FirmwareHex)) {
        throw "Missing firmware hex: $FirmwareHex"
    }
    if ((Get-Item $FirmwareBin).Length -gt 0x4000) {
        throw "Firmware binary exceeds 16 KiB Boot ROM: $((Get-Item $FirmwareBin).Length) bytes"
    }

    return ,@{
        Hex = $FirmwareHex
        Bin = $FirmwareBin
        Elf = $FirmwareElf
        Cross = $Cross
        Python = $Python
        Make = $Make
    }
}

function Initialize-QuestaWork {
    param(
        [string]$BuildDir
    )

    New-SoCDirectory -Path $BuildDir
    Remove-SoCDirectorySafe -Path (Join-Path $BuildDir "work") -Root $BuildDir

    Push-Location $BuildDir
    try {
        Invoke-SoCExternal -FilePath "vlib" -ArgumentList @("work") -ErrorMessage "vlib failed"
    }
    finally {
        Pop-Location
    }
}

function Invoke-SoCQuestaSim {
    param(
        [string]$Top,
        [string[]]$PlusArgs = @(),
        [string]$ExpectedPass = "PASS:"
    )

    $LogPath = Join-Path (Get-Location) "$Top.vsim.log"
    Remove-Item -LiteralPath $LogPath -Force -ErrorAction SilentlyContinue

    & vsim -c $Top @PlusArgs -l $LogPath -do "run -all; quit -f"
    $ExitCode = $LASTEXITCODE
    if ($ExitCode -ne 0) {
        throw "vsim failed for $Top"
    }
    if (-not (Test-Path $LogPath)) {
        throw "Missing vsim log for $Top"
    }

    $LogText = Get-Content -LiteralPath $LogPath -Raw
    if ($LogText -match '(\*\* Fatal:|Errors:\s*[1-9][0-9]*)') {
        throw "vsim reported failure for $Top"
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedPass) -and
        ($LogText -notmatch [regex]::Escape($ExpectedPass))) {
        throw "vsim log for $Top did not contain expected pass marker: $ExpectedPass"
    }
}
