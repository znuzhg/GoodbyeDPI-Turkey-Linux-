# Windows support

This directory contains the native Windows backend for this repository. It uses WinDivert for packet capture/reinjection and retains the Windows service, DNS redirection, and TTL-tracking implementation from the Windows upstream project.

## Scope and status

- Target: Windows 10/11, x64.
- Backend: WinDivert 2.2.2-A.
- The Linux backend remains under the repository's existing `src/` directory and is not modified by this port.
- The Windows source is kept under `windows/src/`; it is not yet a shared cross-platform C core.
- CI builds the Windows executable and packages its runtime driver files. A successful compile is not a substitute for real network testing on Windows.

## Build on Windows

Use an MSYS2 **MINGW64** environment with GCC, GNU Make, windres, curl and unzip available on PATH. The build script downloads the pinned WinDivert SDK/runtime archive, verifies its SHA-256, builds the x64 executable and stages the required runtime files under `windows/bin/`.

From the repository root, run in PowerShell:

```powershell
.\windows\build.ps1
```

The script expects the MinGW-w64 compiler tools and GNU Make to be installed. It does not install a kernel driver or register a Windows service.

## Use a prebuilt Windows package

1. Open the repository's [Actions page](https://github.com/znuzhg/GoodbyeDPI-Turkey-Linux-/actions/workflows/windows-build.yml).
2. Open the latest successful **Windows x64 build** run and download the `GoodbyeDPI-Turkey-Windows-x64` artifact.
3. Extract the ZIP. The extracted folder contains `run.cmd`, the service scripts, and a `bin` folder containing `goodbyedpi.exe` plus the WinDivert runtime files.
4. Open PowerShell in that extracted folder **as Administrator** and run:

```powershell
.\\run.cmd
```

Start with the one-time console mode. Stop it with Ctrl+C. Do not install the auto-start service until the one-time run has been checked on your connection.

To install the service later, run `.\install_service.cmd` from the same elevated PowerShell window. To remove it, run `.\remove_service.cmd`.

## Run once

Open an elevated terminal (Run as administrator), then run:

```cmd
windows\run.cmd
```

Stop the process with Ctrl+C. The bundled executable manifest also requests administrator privileges.

## Install as a Windows service

Run `windows\install_service.cmd` as administrator. It registers the `GoodbyeDPI` service for automatic startup and starts it immediately.

To remove the service, run `windows\remove_service.cmd` as administrator. The removal script only removes this application's service entry; it does not delete shared WinDivert driver services from the machine.

## Build dependency

- Archive: `https://github.com/basil00/WinDivert/releases/download/v2.2.2/WinDivert-2.2.2-A.zip`
- SHA-256: `63cb41763bb4b20f600b6de04e991a9c2be73279e317d4d82f237b150c5f3f15`

WinDivert DLL and SYS files are downloaded during build and are not committed to this repository. Keep the DLL and driver in the same runtime directory as `goodbyedpi.exe`.

## Source and licensing

The Windows implementation in `windows/src/` is derived from [cagritaskn/GoodbyeDPI-Turkey](https://github.com/cagritaskn/GoodbyeDPI-Turkey), upstream commit `cb83565af1edfc6d80f53d98ca32a41fa6bc0862`. The upstream project credits the original [ValdikSS/GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) project.

The imported Windows source is distributed under Apache License 2.0. Its license text is included as `windows/LICENSE-APACHE-2.0.txt`. The Linux implementation and Windows implementation retain separate source trees and license/provenance notices.

## Verification status

GitHub Actions performs a reproducible x64 cross-compile and packages `run.cmd`, service scripts, and a `bin/` directory containing the executable and WinDivert DLL/SYS runtime files. Packet-handling behavior must still be validated on Windows 10/11 with a real network and packet capture before describing the port as production-ready.
