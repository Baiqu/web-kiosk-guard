# PyInstaller spec for a single-file WebKioskGuard.exe.
#
# Why a spec instead of a plain CLI command: PyInstaller collects the Windows
# "API set" stub DLLs (api-ms-win-*.dll) from the build machine and bundles
# them. On Windows 10/11 those names are virtual API sets the OS resolves
# internally to kernelbase.dll — a bundled physical stub can SHADOW the OS one
# and then fail to load, producing errors like
#   "api-ms-win-core-path-l1-1-0.dll is missing".
# We strip those stubs from the bundle so the OS resolves them natively.

from PyInstaller.utils.hooks import collect_all

datas, binaries, hiddenimports = [], [], []
for pkg in ("webview", "clr_loader"):
    d, b, h = collect_all(pkg)
    datas += d
    binaries += b
    hiddenimports += h

a = Analysis(
    ["src/main.py"],
    pathex=["src"],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
)

# Drop Windows API-set stub DLLs; let the OS resolve them natively.
a.binaries = [b for b in a.binaries if not b[0].lower().startswith("api-ms-win")]

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="WebKioskGuard",
    console=False,
    upx=False,
)
