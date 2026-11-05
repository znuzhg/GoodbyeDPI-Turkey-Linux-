#requires -Version 5.1
# Build the native Windows x64 backend. Supports Windows PowerShell 5.1 and PowerShell 7+.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

$script:PowerShellVersion = $PSVersionTable.PSVersion
$script:PowerShellEdition = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { 'Desktop' }
Write-Host "PowerShell: $script:PowerShellEdition $script:PowerShellVersion"

if ($env:OS -ne 'Windows_NT') {
    throw 'This build script must run on Windows.'
}
if (-not [Environment]::Is64BitOperatingSystem -or
    $env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or
    $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
    throw 'This backend currently targets x64 Windows only.'
}

# Windows PowerShell 5.1 may otherwise negotiate an older TLS version on some machines.
if ($script:PowerShellEdition -eq 'Desktop') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

function Invoke-CompatDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [hashtable]$Headers
    )

    $request = @{
        Uri = $Uri
        OutFile = $OutFile
        TimeoutSec = 900
        ErrorAction = 'Stop'
    }
    if ($Headers) {
        $request.Headers = $Headers
    }

    # -UseBasicParsing is needed for compatibility with Windows PowerShell 5.1.
    if ($script:PowerShellVersion.Major -le 5) {
        $request.UseBasicParsing = $true
    }

    Invoke-WebRequest @request
}

function Test-AsciiNoSpacePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return ($Path -notmatch '[^\x21-\x7E]')
}

function Test-WritableEmptyDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        if (Test-Path -LiteralPath $Path) {
            if (Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1) {
                return $false
            }
        } else {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }

        $probe = Join-Path $Path '.goodbyedpi-write-test'
        [System.IO.File]::WriteAllText($probe, 'test')
        Remove-Item -LiteralPath $probe -Force
        return $true
    } catch {
        return $false
    }
}

function Invoke-MsysBash {
    param(
        [Parameter(Mandatory = $true)][string]$BashPath,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    & $BashPath -lc $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage (exit code $LASTEXITCODE)."
    }
}

$windowsDir = $PSScriptRoot
$sourceDir = Join-Path $windowsDir 'src'
if (-not (Test-Path -LiteralPath (Join-Path $sourceDir 'Makefile'))) {
    throw "Windows source tree was not found: $sourceDir"
}

# MSYS2 and GNU Make are unreliable in non-ASCII/space-containing build paths.
# Stage source and dependencies in a short ASCII-only temporary directory.
$stagingCandidates = @()
if ($env:TEMP) {
    $stagingCandidates += (Join-Path $env:TEMP 'gdpibuild')
}
$stagingCandidates += 'C:\gdpibuild'

$stagingRoot = $null
foreach ($candidate in $stagingCandidates) {
    if (Test-AsciiNoSpacePath -Path $candidate -and
        (Test-WritableEmptyDirectory -Path $candidate)) {
        $stagingRoot = $candidate
        break
    }
}
if (-not $stagingRoot) {
    throw 'Could not create an ASCII-only temporary build directory. Ensure C:\gdpibuild or %TEMP%\gdpibuild is writable and contains no spaces or non-ASCII characters.'
}

$cacheDir = Join-Path $stagingRoot 'cache'
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

# Find an existing MSYS2 install before downloading one.
$msysRoots = @()
if ($env:MSYS2_ROOT) {
    $msysRoots += $env:MSYS2_ROOT
}
$msysRoots += 'C:\msys64'
if ($env:LOCALAPPDATA) {
    $msysRoots += (Join-Path $env:LOCALAPPDATA 'msys64')
}

$msysRoot = $null
foreach ($candidate in ($msysRoots | Select-Object -Unique)) {
    if (Test-Path -LiteralPath (Join-Path $candidate 'usr\bin\bash.exe')) {
        $msysRoot = $candidate
        break
    }
}

if (-not $msysRoot) {
    Write-Host 'MSYS2 was not found. Downloading the official x64 installer...'

    # Resolve the current official installer and its SHA-256 digest from the MSYS2
    # installer project's GitHub release metadata. This avoids an unverified binary.
    $releaseApi = 'https://api.github.com/repos/msys2/msys2-installer/releases/tags/nightly-x86_64'
    $release = Invoke-RestMethod -Uri $releaseApi -Headers @{ 'User-Agent' = 'GoodbyeDPI-Turkey-build' } -TimeoutSec 60
    $installerAsset = $release.assets |
        Where-Object { $_.name -eq 'msys2-x86_64-latest.exe' } |
        Select-Object -First 1

    if (-not $installerAsset -or -not $installerAsset.browser_download_url -or
        -not $installerAsset.digest -or $installerAsset.digest -notmatch '^sha256:[0-9a-fA-F]{64}$') {
        throw 'Could not resolve the official MSYS2 installer and its SHA-256 digest from GitHub release metadata.'
    }

    $installerPath = Join-Path $cacheDir 'msys2-x86_64-latest.exe'
    Invoke-CompatDownload -Uri $installerAsset.browser_download_url -OutFile $installerPath
    $expectedInstallerHash = $installerAsset.digest.Substring(7).ToLowerInvariant()
    $actualInstallerHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualInstallerHash -ne $expectedInstallerHash) {
        Remove-Item -LiteralPath $installerPath -Force
        throw "MSYS2 installer SHA-256 mismatch. Expected $expectedInstallerHash; received $actualInstallerHash."
    }
    Write-Host "MSYS2 installer SHA-256 verified: $actualInstallerHash"

    # Prefer a per-user location so Administrator privileges are not needed to build.
    $installCandidates = @()
    if ($env:LOCALAPPDATA) {
        $installCandidates += (Join-Path $env:LOCALAPPDATA 'msys64')
    }
    $installCandidates += 'C:\msys64'

    $installRoot = $null
    foreach ($candidate in ($installCandidates | Select-Object -Unique)) {
        if ((Test-AsciiNoSpacePath -Path $candidate) -and
            (Test-WritableEmptyDirectory -Path $candidate)) {
            $installRoot = $candidate
            break
        }
    }
    if (-not $installRoot) {
        throw 'No writable ASCII-only MSYS2 install path was found. Create an empty C:\msys64 folder or set MSYS2_ROOT to an existing installation.'
    }

    $installerRootArgument = $installRoot.Replace('\', '/')
    Write-Host "Installing MSYS2 to $installRoot ..."
    & $installerPath 'in' '--confirm-command' '--accept-messages' '--root' $installerRootArgument
    if ($LASTEXITCODE -ne 0) {
        throw "MSYS2 installer failed (exit code $LASTEXITCODE)."
    }

    if (-not (Test-Path -LiteralPath (Join-Path $installRoot 'usr\bin\bash.exe'))) {
        throw 'MSYS2 installer completed but usr\bin\bash.exe was not found.'
    }
    $msysRoot = $installRoot
}

$bashPath = Join-Path $msysRoot 'usr\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bashPath)) {
    throw "MSYS2 bash.exe was not found under $msysRoot."
}

# MSYS2's own documentation recommends running pacman from a login shell.
$env:MSYSTEM = 'MINGW64'
$env:CHERE_INVOKING = 'yes'
Write-Host "Using MSYS2: $msysRoot"
Write-Host 'Updating MSYS2 package database and installing MINGW64 GCC + GNU Make...'

Invoke-MsysBash -BashPath $bashPath -Command ' ' -FailureMessage 'MSYS2 first-run initialization failed'
Invoke-MsysBash -BashPath $bashPath -Command 'pacman --noconfirm -Syuu' -FailureMessage 'MSYS2 core update failed'
Invoke-MsysBash -BashPath $bashPath -Command 'pacman --noconfirm -Syuu' -FailureMessage 'MSYS2 package update failed'
Invoke-MsysBash -BashPath $bashPath -Command 'pacman --noconfirm -S --needed make mingw-w64-x86_64-gcc' -FailureMessage 'Installing GNU Make and MinGW-w64 GCC failed'
Invoke-MsysBash -BashPath $bashPath -Command 'command -v make && command -v gcc && command -v windres' -FailureMessage 'GNU Make, GCC or windres is still missing'

# Download and verify the pinned WinDivert SDK/runtime.
$version = 'WinDivert-2.2.2-A'
$winDivertSha256 = '63cb41763bb4b20f600b6de04e991a9c2be73279e317d4d82f237b150c5f3f15'
$winDivertUrl = 'https://github.com/basil00/WinDivert/releases/download/v2.2.2/WinDivert-2.2.2-A.zip'
$archive = Join-Path $cacheDir "$version.zip"
$actualWinDivertHash = $null

if (Test-Path -LiteralPath $archive) {
    $actualWinDivertHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
}
if ($actualWinDivertHash -ne $winDivertSha256) {
    if (Test-Path -LiteralPath $archive) {
        Remove-Item -LiteralPath $archive -Force
    }
    Write-Host "Downloading pinned $version archive..."
    Invoke-CompatDownload -Uri $winDivertUrl -OutFile $archive
    $actualWinDivertHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
}
if ($actualWinDivertHash -ne $winDivertSha256) {
    throw "WinDivert archive SHA-256 mismatch. Expected $winDivertSha256; got $actualWinDivertHash. The archive was not extracted."
}
Write-Host "WinDivert SHA-256 verified: $actualWinDivertHash"

# Copy the source tree into the ASCII-only staging directory before invoking MSYS2.
$workDir = Join-Path $stagingRoot 'work'
$stagedSource = Join-Path $workDir 'src'
$stagedDeps = Join-Path $workDir 'deps'
if (Test-Path -LiteralPath $workDir) {
    Remove-Item -LiteralPath $workDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stagedSource, $stagedDeps | Out-Null
Copy-Item -Path (Join-Path $sourceDir '*') -Destination $stagedSource -Recurse -Force
Expand-Archive -LiteralPath $archive -DestinationPath $stagedDeps -Force

$runtimeDir = Join-Path (Join-Path $stagedDeps $version) 'x64'
if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $stagedDeps $version) 'include\windivert.h'))) {
    throw 'The verified WinDivert archive does not contain include\windivert.h.'
}

Push-Location $stagedSource
try {
    Invoke-MsysBash -BashPath $bashPath -Command 'make clean' -FailureMessage 'make clean failed'
    Invoke-MsysBash -BashPath $bashPath -Command "make BIT64=1 WINDIVERT_DIR=../deps/$version" -FailureMessage 'Windows x64 compilation failed'
} finally {
    Pop-Location
}

$builtExe = Join-Path $stagedSource 'goodbyedpi.exe'
if (-not (Test-Path -LiteralPath $builtExe)) {
    throw 'Build did not produce goodbyedpi.exe.'
}

$runtimeFiles = Get-ChildItem -LiteralPath $runtimeDir -File |
    Where-Object { $_.Extension -in '.dll', '.sys' }
if (-not ($runtimeFiles | Where-Object { $_.Extension -eq '.dll' }) -or
    -not ($runtimeFiles | Where-Object { $_.Extension -eq '.sys' })) {
    throw 'The pinned WinDivert archive did not contain the expected x64 DLL and SYS runtime files.'
}

$binDir = Join-Path $windowsDir 'bin'
if (Test-Path -LiteralPath $binDir) {
    Remove-Item -LiteralPath $binDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
Copy-Item -LiteralPath $builtExe -Destination $binDir -Force
$runtimeFiles | Copy-Item -Destination $binDir -Force

Write-Host ''
Write-Host "Build complete: $(Join-Path $binDir 'goodbyedpi.exe')"
Write-Host "PowerShell compatibility path: $script:PowerShellEdition $script:PowerShellVersion"
Write-Host 'Run .\run.cmd from the windows folder, or open it as Administrator to start GoodbyeDPI.'
Write-Host "ASCII build workspace: $workDir"
