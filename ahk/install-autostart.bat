@echo off
REM Double-click to make WebKioskGuardAHK.exe start automatically when you log in.
REM Creates a shortcut in your Startup folder. No admin rights needed.
setlocal
set "EXE=%~dp0WebKioskGuardAHK.exe"
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "LNK=%STARTUP%\WebKioskGuard.lnk"

if not exist "%EXE%" (
  echo.
  echo ERROR: WebKioskGuardAHK.exe was not found next to this script.
  echo Put this .bat in the same folder as the exe, then run it again.
  echo.
  pause
  exit /b 1
)

powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut('%LNK%'); $s.TargetPath='%EXE%'; $s.WorkingDirectory='%~dp0'; $s.WindowStyle=1; $s.Save()"

if exist "%LNK%" (
  echo.
  echo Done. WebKioskGuard will now start automatically at login.
  echo Shortcut: %LNK%
) else (
  echo.
  echo Failed to create the startup shortcut.
)
echo.
pause
