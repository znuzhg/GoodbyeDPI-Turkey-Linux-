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

set "SERVICE_ARGS=-5 --set-ttl 5 --dns-addr 77.88.8.8 --dns-port 1253 --dnsv6-addr 2a02:6b8::feed:0ff --dnsv6-port 1253"
set "SERVICE_BINPATH=\"%EXE%\" %SERVICE_ARGS%"

sc.exe query GoodbyeDPI >nul 2>&1
if errorlevel 1 (
  echo Creating GoodbyeDPI service...
  sc.exe create GoodbyeDPI binPath= "%SERVICE_BINPATH%" start= auto
  if errorlevel 1 (
    echo Failed to register the GoodbyeDPI service.
    exit /b 1
  )
) else (
  sc.exe qc GoodbyeDPI | findstr.exe /I /C:"%EXE%" >nul
  if errorlevel 1 (
    echo A GoodbyeDPI service already exists but points to a different executable.
    echo Refusing to stop, replace, or delete another installation.
    echo Remove that installation using its own remove_service.cmd first.
    exit /b 1
  )

  echo Updating the existing GoodbyeDPI service at this installation path...
  sc.exe stop GoodbyeDPI >nul 2>&1
  call :wait_for_stop
  if errorlevel 1 (
    echo GoodbyeDPI service did not stop within 15 seconds.
    exit /b 1
  )

  sc.exe config GoodbyeDPI binPath= "%SERVICE_BINPATH%" start= auto
  if errorlevel 1 (
    echo Failed to update the existing GoodbyeDPI service configuration.
    exit /b 1
  )
)

sc.exe description GoodbyeDPI "GoodbyeDPI Turkey Windows packet processing service"
sc.exe start GoodbyeDPI
if errorlevel 1 (
  echo The service was registered but did not start. Check the Windows event log.
  exit /b 1
)
echo GoodbyeDPI service installed and started.
echo Do not move this folder while the service is installed.
exit /b 0

:wait_for_stop
for /L %%I in (1,1,15) do (
  sc.exe query GoodbyeDPI | findstr.exe /I "STOPPED" >nul
  if not errorlevel 1 exit /b 0
  timeout /t 1 /nobreak >nul
)
exit /b 1
