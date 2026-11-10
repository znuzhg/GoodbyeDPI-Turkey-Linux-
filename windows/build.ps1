#requires -Version 5.1
# Native Windows x64 build. Supports Windows PowerShell 5.1 and PowerShell 7+.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

$script:PowerShellVersion = $PSVersionTable.PSVersion
$script:PowerShellEdition = if ($PSVersionTable.PSEdition) {
    $PSVersionTable.PSEdition
} else {
    'Desktop'
}
Write-Host "PowerShell: $script:PowerShellEdition $script:PowerShellVersion"

if ($env:OS -ne 'Windows_NT') {
    throw 'This build script must run on Windows.'
}
if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'This backend currently targets 64-bit Windows only.'
}
if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or
    $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
    throw 'This backend currently targets x64 Windows, not Windows on ARM.'
}

# Windows PowerShell 5.1 may otherwise negotiate an older TLS version.
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
    if ($script:PowerShellVersion.Major -le 5) {
        # Required for reliable downloads with Windows PowerShell 5.1.
        $request.UseBasicParsing = $true
    }

    Invoke-WebRequest @request
}

function Test-AsciiNoSpacePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return ($Path -notmatch '[^\x21-\x7E]')
}

function Test-WritableDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        $probe = Join-Path $Path '.goodbyedpi-write-test'
        [System.IO.File]::WriteAllText($probe, 'test')
        Remove-Item -LiteralPath $probe -Force
        return $true
    } catch {
        return $false
    }
}

function Test-WritableEmptyDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        if (Test-Path -LiteralPath $Path) {
            $existing = Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1
            if ($null -ne $existing) {
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

# MSYS2 tools can fail in paths containing Turkish characters or spaces.
# Compile in a short ASCII-only workspace, then copy outputs back to windows\bin.
$stagingCandidates = @()
if ($env:TEMP) {
    $stagingCandidates += (Join-Path $env:TEMP 'gdpibuild')
}
$stagingCandidates += 'C:\gdpibuild'

$stagingRoot = $null
foreach ($candidate in $stagingCandidates) {
    if ((Test-AsciiNoSpacePath -Path $candidate) -and
        (Test-WritableDirectory -Path $candidate)) {
        $stagingRoot = $candidate
        break
    }
}
if (-not $stagingRoot) {
    throw 'Could not create an ASCII-only temporary build directory. Make %TEMP%\gdpibuild or C:\gdpibuild writable.'
}

$cacheDir = Join-Path $stagingRoot 'cache'
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

# MSYS2_ROOT overrides automatic discovery. If set to a new empty directory,
# the script installs MSYS2 there; this is also used by the clean-bootstrap CI job.
$requestedMsysRoot = $null
if (-not [string]::IsNullOrWhiteSpace($env:MSYS2_ROOT)) {
    $requestedMsysRoot = [System.IO.Path]::GetFullPath($env:MSYS2_ROOT)
}

$msysRoot = $null
if ($requestedMsysRoot) {
    if (Test-Path -LiteralPath (Join-Path $requestedMsysRoot 'usr\bin\bash.exe')) {
        $msysRoot = $requestedMsysRoot
    }
} else {
    $msysRoots = @('C:\msys64')
    if ($env:LOCALAPPDATA) {
        $msysRoots += (Join-Path $env:LOCALAPPDATA 'msys64')
    }

    foreach ($candidate in ($msysRoots | Select-Object -Unique)) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'usr\bin\bash.exe')) {
            $msysRoot = $candidate
            break
        }
    }
}

if (-not $msysRoot) {
    # Pin a dated stable MSYS2 release so bootstrap does not depend on the
    # /releases/latest endpoint, which may point at the rolling nightly channel.
    $msys2ReleaseTag = '2026-09-27'
    $installerName = 'msys2-x86_64-20260927.exe'
    $installerUrl = 'https://github.com/msys2/msys2-installer/releases/download/2026-09-27/msys2-x86_64-20260927.exe'
    $expectedInstallerHash = '416d506c839a2da4bc184eeec8cbaaf1055ee698618228c62dfc4232a6970f0e'
    $installerPath = Join-Path $cacheDir $installerName

    Write-Host "MSYS2 was not found. Using official stable release $msys2ReleaseTag."
    Invoke-CompatDownload -Uri $installerUrl -OutFile $installerPath

    $actualInstallerHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualInstallerHash -ne $expectedInstallerHash) {
        Remove-Item -LiteralPath $installerPath -Force
        throw "MSYS2 installer SHA-256 mismatch. Expected $expectedInstallerHash; received $actualInstallerHash."
    }
    Write-Host "MSYS2 installer SHA-256 verified: $actualInstallerHash"

    # Require the Windows publisher signature too. This confirms signer/integrity,
    # but does not claim the installer or any payload is malware-free.
    $installerSignature = Get-AuthenticodeSignature -LiteralPath $installerPath
    if ($installerSignature.Status -ne 'Valid') {
        throw "MSYS2 installer Authenticode verification failed: $($installerSignature.Status). $($installerSignature.StatusMessage)"
    }
    Write-Host "MSYS2 signer: $($installerSignature.SignerCertificate.Subject)"

    # Prefer a per-user install. A caller-supplied root is used exactly as requested.
    $installCandidates = @()
    if ($requestedMsysRoot) {
        $installCandidates += $requestedMsysRoot
    } else {
        if ($env:LOCALAPPDATA) {
            $installCandidates += (Join-Path $env:LOCALAPPDATA 'msys64')
        }
        $installCandidates += 'C:\msys64'
    }

    $installRoot = $null
    foreach ($candidate in ($installCandidates | Select-Object -Unique)) {
        if ((Test-AsciiNoSpacePath -Path $candidate) -and
            (Test-WritableEmptyDirectory -Path $candidate)) {
            $installRoot = $candidate
            break
        }
    }
    if (-not $installRoot) {
        throw 'No writable empty ASCII-only MSYS2 install directory was found. Remove an incomplete install or set MSYS2_ROOT to a new empty directory.'
    }

    $installerRootArgument = $installRoot.Replace('\', '/')
    Write-Host "Installing MSYS2 to $installRoot ..."
    & $installerPath 'in' '--confirm-command' '--accept-messages' '--root' $installerRootArgument
    if ($LASTEXITCODE -ne 0) {
        throw "MSYS2 installer failed (exit code $LASTEXITCODE)."
    }

    $installedBash = Join-Path $installRoot 'usr\bin\bash.exe'
    if (-not (Test-Path -LiteralPath $installedBash)) {
        throw "MSYS2 installer completed but bash.exe was not found at $installedBash"
    }
    $msysRoot = $installRoot
}

$bashPath = Join-Path $msysRoot 'usr\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bashPath)) {
    throw "MSYS2 bash.exe was not found under $msysRoot."
}

# UCRT64 is MSYS2's recommended 64-bit GCC environment. MINGW64 is legacy.
$env:MSYSTEM = 'UCRT64'
$env:CHERE_INVOKING = 'yes'
Write-Host "Using MSYS2: $msysRoot"
Write-Host 'Updating MSYS2 packages and installing UCRT64 GCC + GNU Make...'

# Run the full update twice: the first pass may update the MSYS2 runtime itself.
Invoke-MsysBash -BashPath $bashPath -Command ' ' -FailureMessage 'MSYS2 first-run initialization failed'
Invoke-MsysBash -BashPath $bashPath -Command 'pacman -Syu --noconfirm' -FailureMessage 'MSYS2 core update failed'
Invoke-MsysBash -BashPath $bashPath -Command 'pacman -Syu --noconfirm' -FailureMessage 'MSYS2 package update failed'
Invoke-MsysBash -BashPath $bashPath -Command 'pacman -S --needed --noconfirm make mingw-w64-ucrt-x86_64-gcc' -FailureMessage 'Installing UCRT64 GNU Make and GCC failed'
Invoke-MsysBash -BashPath $bashPath -Command 'command -v make && command -v gcc && command -v windres' -FailureMessage 'GNU Make, GCC or windres is still missing'

# Download and verify the pinned WinDivert SDK/runtime archive.
$winDivertVersion = 'WinDivert-2.2.2-A'
$winDivertSha256 = '63cb41763bb4b20f600b6de04e991a9c2be73279e317d4d82f237b150c5f3f15'
$winDivertUrl = 'https://github.com/basil00/WinDivert/releases/download/v2.2.2/WinDivert-2.2.2-A.zip'
$archive = Join-Path $cacheDir "$winDivertVersion.zip"

$actualWinDivertHash = $null
if (Test-Path -LiteralPath $archive) {
    $actualWinDivertHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
}
if ($actualWinDivertHash -ne $winDivertSha256) {
    if (Test-Path -LiteralPath $archive) {
        Remove-Item -LiteralPath $archive -Force
    }
    Write-Host "Downloading pinned $winDivertVersion archive..."
    Invoke-CompatDownload -Uri $winDivertUrl -OutFile $archive
    $actualWinDivertHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
}
if ($actualWinDivertHash -ne $winDivertSha256) {
    throw "WinDivert archive SHA-256 mismatch. Expected $winDivertSha256; got $actualWinDivertHash."
}
Write-Host "WinDivert SHA-256 verified: $actualWinDivertHash"

# Stage the source and dependency archive in the ASCII-only workspace.
$workDir = Join-Path $stagingRoot 'work'
$stagedSource = Join-Path $workDir 'src'
$stagedDeps = Join-Path $workDir 'deps'
if (Test-Path -LiteralPath $workDir) {
    Remove-Item -LiteralPath $workDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stagedSource, $stagedDeps | Out-Null
Copy-Item -Path (Join-Path $sourceDir '*') -Destination $stagedSource -Recurse -Force
Expand-Archive -LiteralPath $archive -DestinationPath $stagedDeps -Force

$dependencyRoot = Join-Path $stagedDeps $winDivertVersion
$runtimeDir = Join-Path $dependencyRoot 'x64'
if (-not (Test-Path -LiteralPath (Join-Path $dependencyRoot 'include\windivert.h'))) {
    throw 'The verified WinDivert archive does not contain include\windivert.h.'
}

Push-Location $stagedSource
try {
    Invoke-MsysBash -BashPath $bashPath -Command 'make clean' -FailureMessage 'make clean failed'
    Invoke-MsysBash -BashPath $bashPath -Command "make BIT64=1 WINDIVERT_DIR=../deps/$winDivertVersion" -FailureMessage 'Windows x64 compilation failed'
} finally {
    Pop-Location
}

$builtExe = Join-Path $stagedSource 'goodbyedpi.exe'
if (-not (Test-Path -LiteralPath $builtExe)) {
    throw 'Build did not produce goodbyedpi.exe.'
}

$runtimeFiles = @(Get-ChildItem -LiteralPath $runtimeDir -File |
    Where-Object { $_.Extension -in '.dll', '.sys' })
$driverFiles = @($runtimeFiles | Where-Object { $_.Extension -eq '.sys' })
if (-not ($runtimeFiles | Where-Object { $_.Extension -eq '.dll' }) -or
    $driverFiles.Count -eq 0) {
    throw 'The pinned WinDivert archive did not contain the expected x64 DLL and SYS runtime files.'
}

# Verify kernel-driver signatures before placing them in the runtime package.
# A valid Authenticode signature is not an antivirus-clean verdict.
foreach ($driverFile in $driverFiles) {
    $driverSignature = Get-AuthenticodeSignature -LiteralPath $driverFile.FullName
    if ($driverSignature.Status -ne 'Valid') {
        throw "WinDivert driver signature verification failed for $($driverFile.Name): $($driverSignature.Status). $($driverSignature.StatusMessage)"
    }
    Write-Host "WinDivert driver signer ($($driverFile.Name)): $($driverSignature.SignerCertificate.Subject)"
}

$binDir = Join-Path $windowsDir 'bin'
# Preserve unrelated user files in windows\bin. Replace only the executable
# and the verified WinDivert runtime files produced by this build.
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
Copy-Item -LiteralPath $builtExe -Destination $binDir -Force
$runtimeFiles | Copy-Item -Destination $binDir -Force

Write-Host ''
Write-Host "Build complete: $(Join-Path $binDir 'goodbyedpi.exe')"
Write-Host "PowerShell compatibility path: $script:PowerShellEdition $script:PowerShellVersion"
Write-Host 'Run .\run.cmd from the windows folder, or open it as Administrator to start GoodbyeDPI.'
Write-Host "ASCII build workspace: $workDir"
