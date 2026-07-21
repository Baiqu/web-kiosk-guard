@echo off
setlocal EnableExtensions
REM undo-kiosk.bat — reverse setup-kiosk.bat:
REM   * remove the login auto-start shortcut, and
REM   * disable Windows auto-login (so a password/login is required again).
REM Needs administrator rights (it asks for them automatically).

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo.
echo === Remove auto-start shortcut ===
set "LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\WebKioskGuard.lnk"
if exist "%LNK%" ( del "%LNK%" & echo   Removed: %LNK% ) else ( echo   None found. )

echo.
echo === Disable auto-login ===
set "WL=HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
reg add "%WL%" /v AutoAdminLogon /t REG_SZ /d 0 /f >nul
reg delete "%WL%" /v DefaultPassword /f >nul 2>&1
echo   Auto-login disabled.

echo.
echo Done. A normal login is required again on next boot.
echo.
pause
