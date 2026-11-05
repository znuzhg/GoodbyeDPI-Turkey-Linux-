@echo off
setlocal
net session >nul 2>&1
if errorlevel 1 (
  echo Run this script from an elevated Administrator terminal.
  exit /b 1
)

set "EXE=%~dp0bin\goodbyedpi.exe"
if not exist "%EXE%" (
  echo Windows backend not built. Starting automatic setup and build...
  where pwsh.exe >nul 2>&1
  if not errorlevel 1 (
    pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
  ) else (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
  )
  if errorlevel 1 (
    echo Automatic build failed. Read the error above and check windows\README.md.
    exit /b 1
  )
)

if not exist "%EXE%" (
  echo Build finished without creating goodbyedpi.exe.
  exit /b 1
)

sc.exe stop GoodbyeDPI >nul 2>&1
sc.exe delete GoodbyeDPI >nul 2>&1
sc.exe create GoodbyeDPI binPath= "\"%EXE%\" -5 --set-ttl 5 --dns-addr 77.88.8.8 --dns-port 1253 --dnsv6-addr 2a02:6b8::feed:0ff --dnsv6-port 1253" start= auto
if errorlevel 1 (
  echo Failed to register the GoodbyeDPI service.
  exit /b 1
)
sc.exe description GoodbyeDPI "GoodbyeDPI Turkey Windows packet processing service"
sc.exe start GoodbyeDPI
if errorlevel 1 (
  echo The service was registered but did not start. Check the Windows event log.
  exit /b 1
)
echo GoodbyeDPI service installed and started.
