@echo off
REM Double-click to stop WebKioskGuardAHK.exe from starting automatically at login.
setlocal
set "LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\WebKioskGuard.lnk"

if exist "%LNK%" (
  del "%LNK%"
  echo Removed auto-start entry.
) else (
  echo No auto-start entry was found.
)
echo.
pause
