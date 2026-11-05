@echo off
setlocal
net session >nul 2>&1
if errorlevel 1 (
  echo Run this script from an elevated Administrator terminal.
  exit /b 1
)
sc.exe stop GoodbyeDPI >nul 2>&1
timeout /t 2 /nobreak >nul
sc.exe delete GoodbyeDPI
if errorlevel 1 (
  echo The GoodbyeDPI service could not be removed or was not installed.
  exit /b 1
)
echo GoodbyeDPI service removed.
echo WinDivert driver files are left untouched for safety.
