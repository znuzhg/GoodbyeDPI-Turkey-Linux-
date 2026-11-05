@echo off
setlocal
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
    echo.
    echo Automatic build failed. Read the error above and check windows\README.md.
    exit /b 1
  )
)

if not exist "%EXE%" (
  echo Build finished without creating goodbyedpi.exe.
  exit /b 1
)

"%EXE%" -5 --set-ttl 5 --dns-addr 77.88.8.8 --dns-port 1253 --dnsv6-addr 2a02:6b8::feed:0ff --dnsv6-port 1253
