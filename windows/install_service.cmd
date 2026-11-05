@echo off
setlocal
net session >nul 2>&1
if errorlevel 1 (
  echo Run this script from an elevated Administrator terminal.
  exit /b 1
)

set "EXE=%~dp0bin\goodbyedpi.exe"
if not exist "%EXE%" (
  echo goodbyedpi.exe was not found. Build the Windows backend first.
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
