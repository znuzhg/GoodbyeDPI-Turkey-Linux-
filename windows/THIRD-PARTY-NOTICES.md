# Third-party notices

## WinDivert 2.2.2-A

The Windows package contains the unmodified x64 WinDivert runtime components from the official WinDivert 2.2.2 release:

- Project: https://github.com/basil00/WinDivert
- Source tag: https://github.com/basil00/WinDivert/tree/v2.2.2
- Binary archive: https://github.com/basil00/WinDivert/releases/download/v2.2.2/WinDivert-2.2.2-A.zip
- Archive SHA-256: `63cb41763bb4b20f600b6de04e991a9c2be73279e317d4d82f237b150c5f3f15`
- Upstream license: `WINDIVERT-LICENSE.txt`

WinDivert is dual-licensed by its upstream authors under the GNU Lesser General Public License (LGPL) version 3 or the GNU General Public License (GPL) version 2. This distribution relies on the LGPLv3 option for the separately supplied, dynamically loaded WinDivert library. The executable loads `WinDivert.dll` at runtime from the application directory; users can replace that DLL with an interface-compatible build. The bundled WinDivert driver is the upstream, unmodified driver.

The complete upstream dual-license text is included as `WINDIVERT-LICENSE.txt`. The complete corresponding upstream source is available at the exact source tag above. No WinDivert source modifications are made in this repository.

## Windows application source

The imported Windows application source is derived from:

- https://github.com/cagritaskn/GoodbyeDPI-Turkey
- Upstream commit: `cb83565af1edfc6d80f53d98ca32a41fa6bc0862`
- License text: `LICENSE-APACHE-2.0.txt`

The Linux implementation under the repository's `src/` directory is separate from this Windows backend.

## Build tools

MSYS2, MinGW-w64 GCC, GNU Make and related packages are build-time dependencies. They are downloaded from their respective upstream distribution channels during a source build and are not bundled in the Windows runtime package.
