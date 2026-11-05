@echo off
setlocal
set "EXE=%~dp0bin\goodbyedpi.exe"
if not exist "%EXE%" (
  echo goodbyedpi.exe was not found.
  echo First build the Windows backend with: powershell -ExecutionPolicy Bypass -File windows\build.ps1
  exit /b 1
)
"%EXE%" -5 --set-ttl 5 --dns-addr 77.88.8.8 --dns-port 1253 --dnsv6-addr 2a02:6b8::feed:0ff --dnsv6-port 1253
