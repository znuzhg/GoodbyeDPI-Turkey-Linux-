@echo off
setlocal
net session >nul 2>&1
if errorlevel 1 (
  echo Run this script from an elevated Administrator terminal.
  exit /b 1
)

set "EXE=%~dp0bin\goodbyedpi.exe"
sc.exe query GoodbyeDPI >nul 2>&1
if errorlevel 1 (
  echo GoodbyeDPI service is not installed.
  exit /b 0
)

sc.exe qc GoodbyeDPI | findstr.exe /I /C:"%EXE%" >nul
if errorlevel 1 (
  echo The GoodbyeDPI service points to a different executable.
  echo Refusing to stop or delete another installation's service.
  echo Run the matching remove_service.cmd from the installation that owns it.
  exit /b 1
)

sc.exe stop GoodbyeDPI >nul 2>&1
call :wait_for_stop
if errorlevel 1 (
  echo GoodbyeDPI service did not stop within 15 seconds; it was not deleted.
  exit /b 1
)

sc.exe delete GoodbyeDPI
if errorlevel 1 (
  echo The GoodbyeDPI service could not be removed.
  exit /b 1
)
echo GoodbyeDPI service removed.
echo WinDivert driver files are left untouched for safety.
exit /b 0

:wait_for_stop
for /L %%I in (1,1,15) do (
  sc.exe query GoodbyeDPI | findstr.exe /I "STOPPED" >nul
  if not errorlevel 1 exit /b 0
  timeout /t 1 /nobreak >nul
)
exit /b 1
