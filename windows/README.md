# Windows support

This directory contains the native Windows backend for this repository. It uses WinDivert for packet capture/reinjection and retains the Windows service, DNS redirection, and TTL-tracking implementation from the Windows upstream project.

## Scope and status

- Target: Windows 10/11, x64.
- Supported build shells: Windows PowerShell 5.1 and PowerShell 7+.
- Backend: WinDivert 2.2.2-A.
- The Linux backend remains under the repository's existing `src/` directory and is not modified by this port.
- The Windows source is kept under `windows/src/`; it is not yet a shared cross-platform C core.
- CI verifies the Windows x64 cross-compile. The native build script also checks both Windows PowerShell 5.1 and PowerShell 7 in CI.
- A successful compile is not a substitute for real network testing on Windows.

## Build on Windows (automatic setup)

The build script detects the active PowerShell edition/version and supports both Windows PowerShell 5.1 (`powershell.exe`) and PowerShell 7+ (`pwsh.exe`).

When MSYS2 is not already installed, the script downloads the official x64 MSYS2 installer from the `msys2/msys2-installer` GitHub release, verifies the installer against the SHA-256 digest published in GitHub release metadata, and installs it in a user-writable location when possible. It then updates MSYS2 and installs GNU Make plus MinGW-w64 GCC. No separate `pacman` command or manual PATH edit is required.

The script also downloads the pinned WinDivert archive and verifies its SHA-256 before extraction. To avoid MSYS2 path issues with Turkish characters or spaces in the repository path (for example `Masaüstü`), source files and dependencies are staged in an ASCII-only temporary build directory. The resulting executable and WinDivert runtime files are copied back to `windows/bin/`.

From the repository root, run either command:

```powershell
# Windows PowerShell 5.1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\build.ps1

# PowerShell 7+
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\build.ps1
```

Or open a terminal in this directory and run:

```powershell
.\build.ps1
```

The build itself does not require an elevated terminal. Internet access is required for the first-time MSYS2/toolchain and WinDivert downloads. The MSYS2 installer and packages are installed under the current user or another writable ASCII-only location. The script does not install a kernel driver or register a Windows service.

## Run from source

`run.cmd` automatically invokes `build.ps1` when `bin/goodbyedpi.exe` is missing. It prefers PowerShell 7 when `pwsh.exe` is installed and otherwise uses Windows PowerShell 5.1.

Open a terminal in the `windows` folder and run `run.cmd` as Administrator:

```powershell
.\run.cmd
```

Stop the process with Ctrl+C. First test the one-time console mode. The default launcher redirects DNS to Yandex (`77.88.8.8:1253`) and IPv6 DNS to `2a02:6b8::feed:0ff:1253`.

## Use a prebuilt Windows package

1. Open the repository's [Actions page](https://github.com/znuzhg/GoodbyeDPI-Turkey-Linux-/actions/workflows/windows-build.yml).
2. Open the latest successful **Windows x64 build** run and download the `GoodbyeDPI-Turkey-Windows-x64` artifact.
3. Extract the ZIP. The extracted folder contains `run.cmd`, the service scripts, and a `bin` folder containing `goodbyedpi.exe` plus the WinDivert runtime files.
4. Open PowerShell in that extracted folder **as Administrator** and run:

```powershell
.\run.cmd
```

The prebuilt package does not need MSYS2 or a compiler.

## Install as a Windows service

Run `install_service.cmd` as Administrator. If the executable is missing, this script also attempts the automatic build before registering the service. It registers the `GoodbyeDPI` service for automatic startup and starts it immediately.

To remove it, run `remove_service.cmd` as administrator. The removal script only removes this application's service entry; it does not delete shared WinDivert driver services from the machine.

Do not move or rename the installation directory after the service is registered because the service stores the executable path.

## Build dependency

- WinDivert archive: `https://github.com/basil00/WinDivert/releases/download/v2.2.2/WinDivert-2.2.2-A.zip`
- WinDivert SHA-256: `63cb41763bb4b20f600b6de04e991a9c2be73279e317d4d82f237b150c5f3f15`
- MSYS2 installer metadata: `https://api.github.com/repos/msys2/msys2-installer/releases/tags/nightly-x86_64`

WinDivert DLL and SYS files are downloaded during build and are not committed to this repository. Keep the DLL and driver in the same runtime directory as `goodbyedpi.exe`.

## Source and licensing

The Windows implementation in `windows/src/` is derived from [cagritaskn/GoodbyeDPI-Turkey](https://github.com/cagritaskn/GoodbyeDPI-Turkey), upstream commit `cb83565af1edfc6d80f53d98ca32a41fa6bc0862`. The upstream project credits the original [ValdikSS/GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) project.

The imported Windows source is distributed under Apache License 2.0. Its license text is included as `windows/LICENSE-APACHE-2.0.txt`. The Linux implementation and Windows implementation retain separate source trees and license/provenance notices.

## Verification status

GitHub Actions performs the reproducible x64 cross-compile and verifies the PowerShell build path with Windows PowerShell 5.1 and PowerShell 7+. Packet-handling behavior must still be validated on Windows 10/11 with a real network and packet capture before describing the port as production-ready.
