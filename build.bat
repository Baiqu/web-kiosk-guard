@echo off
REM Package Web Kiosk Guard into a single standalone .exe (no Python needed to run).
REM Output: dist\WebKioskGuard.exe  — keep config.json in the SAME folder as the exe.
setlocal
cd /d "%~dp0"

pyinstaller --noconfirm WebKioskGuard.spec

if errorlevel 1 (
  echo Build failed.
  exit /b 1
)

REM Ship an editable config next to the exe (does not overwrite an existing one).
if not exist "dist\config.json" copy "config.json" "dist\config.json" >nul

echo.
echo Done. Run: dist\WebKioskGuard.exe  (edit dist\config.json to change the URL)
