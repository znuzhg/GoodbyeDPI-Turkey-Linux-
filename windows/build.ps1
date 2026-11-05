# Build the native Windows x64 backend.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$version = 'WinDivert-2.2.2-A'
$sha256 = '63cb41763bb4b20f600b6de04e991a9c2be73279e317d4d82f237b150c5f3f15'
$url = 'https://github.com/basil00/WinDivert/releases/download/v2.2.2/WinDivert-2.2.2-A.zip'

$windowsDir = $PSScriptRoot
$depsDir = Join-Path $windowsDir 'deps'
$archive = Join-Path $depsDir "$version.zip"
$extractDir = Join-Path $depsDir $version
$srcDir = Join-Path $windowsDir 'src'
$binDir = Join-Path $windowsDir 'bin'

New-Item -ItemType Directory -Force -Path $depsDir | Out-Null

if (-not (Test-Path (Join-Path $extractDir 'include\windivert.h'))) {
    if (-not (Test-Path $archive)) {
        Write-Host "Downloading pinned $version archive..."
        Invoke-WebRequest -Uri $url -OutFile $archive
    }

    $actualHash = (Get-FileHash -Path $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Host "Downloaded WinDivert SHA-256: $actualHash"
    if ($actualHash -ne $sha256) {
        throw "WinDivert archive SHA-256 mismatch. Expected $sha256; got $actualHash. The archive was not extracted."
    }

    Expand-Archive -Path $archive -DestinationPath $depsDir -Force
}

$makeCommand = Get-Command make -ErrorAction SilentlyContinue
if (-not $makeCommand) {
    $makeCommand = Get-Command mingw32-make -ErrorAction SilentlyContinue
}
if (-not $makeCommand) {
    throw 'GNU Make is required. Install it in the MSYS2 MINGW64 environment and ensure it is on PATH.'
}

$compilerPrefix = ''
if (-not $env:MSYSTEM) {
    if (Get-Command x86_64-w64-mingw32-gcc -ErrorAction SilentlyContinue) {
        $compilerPrefix = 'x86_64-w64-mingw32-'
    } elseif (-not (Get-Command gcc -ErrorAction SilentlyContinue)) {
        throw 'MinGW-w64 GCC is required. Use an MSYS2 MINGW64 shell or install the x86_64-w64-mingw32 toolchain.'
    }
}

Push-Location $srcDir
try {
    & $makeCommand.Source clean
    if ($LASTEXITCODE -ne 0) { throw 'make clean failed.' }

    & $makeCommand.Source 'BIT64=1' "CPREFIX=$compilerPrefix" "WINDIVERT_DIR=../deps/$version"
    if ($LASTEXITCODE -ne 0) { throw 'Windows x64 compilation failed.' }
} finally {
    Pop-Location
}

if (-not (Test-Path (Join-Path $srcDir 'goodbyedpi.exe'))) {
    throw 'Build did not produce goodbyedpi.exe.'
}

New-Item -ItemType Directory -Force -Path $binDir | Out-Null
Copy-Item (Join-Path $srcDir 'goodbyedpi.exe') $binDir -Force
$runtimeDir = Join-Path $extractDir 'x64'
$runtimeFiles = Get-ChildItem -Path $runtimeDir -File | Where-Object { $_.Extension -in '.dll', '.sys' }
if (-not ($runtimeFiles | Where-Object { $_.Extension -eq '.dll' }) -or
    -not ($runtimeFiles | Where-Object { $_.Extension -eq '.sys' })) {
    throw 'The pinned WinDivert archive did not contain the expected x64 DLL and SYS runtime files.'
}
$runtimeFiles | Copy-Item -Destination $binDir -Force

Write-Host "Build complete: $(Join-Path $binDir 'goodbyedpi.exe')"
Write-Host 'Runtime files staged in windows/bin/. Run run.cmd or install_service.cmd as administrator.'
