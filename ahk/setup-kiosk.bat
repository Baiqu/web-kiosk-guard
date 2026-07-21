@echo off
setlocal EnableExtensions
REM setup-kiosk.bat — ONE-SHOT kiosk setup:
REM   1) auto-start WebKioskGuardAHK.exe at login, and
REM   2) enable Windows auto-login for an account WITH NO PASSWORD,
REM      so a reboot goes straight to the desktop and launches the kiosk.
REM
REM Needs administrator rights (it asks for them automatically).
REM Keep this .bat in the SAME folder as WebKioskGuardAHK.exe.
REM To undo everything later, run undo-kiosk.bat.

REM Capture the intended auto-login user BEFORE any elevation changes context.
if "%~1"=="" ( set "TARGETUSER=%USERNAME%" ) else ( set "TARGETUSER=%~1" )

REM Elevate if we are not already administrator, carrying the user through.
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%TARGETUSER%' -Verb RunAs"
  exit /b
)

set "EXE=%~dp0WebKioskGuardAHK.exe"
if not exist "%EXE%" (
  echo.
  echo ERROR: WebKioskGuardAHK.exe was not found next to this script.
  echo Put this .bat in the same folder as the exe, then run it again.
  echo.
  pause
  exit /b 1
)

echo.
echo === 1/2  Auto-start the kiosk at login ===
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "LNK=%STARTUP%\WebKioskGuard.lnk"
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut('%LNK%'); $s.TargetPath='%EXE%'; $s.WorkingDirectory='%~dp0'; $s.WindowStyle=1; $s.Save()"
if exist "%LNK%" ( echo   OK: %LNK% ) else ( echo   FAILED to create startup shortcut )

echo.
echo === 2/2  Enable auto-login (account: %TARGETUSER%, no password) ===
set "WL=HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
reg add "%WL%" /v AutoAdminLogon    /t REG_SZ /d 1               /f >nul
reg add "%WL%" /v DefaultUserName   /t REG_SZ /d "%TARGETUSER%"  /f >nul
reg add "%WL%" /v DefaultDomainName /t REG_SZ /d "%COMPUTERNAME%" /f >nul
reg add "%WL%" /v DefaultPassword   /t REG_SZ /d ""              /f >nul
REM Clear any one-time counter that could suppress auto-login.
reg delete "%WL%" /v AutoLogonCount /f >nul 2>&1
echo   OK: auto-login enabled for %TARGETUSER% on %COMPUTERNAME%

echo.
echo === Extra: never turn off the screen / sleep ===
powercfg /change monitor-timeout-ac 0 >nul 2>&1
powercfg /change monitor-timeout-dc 0 >nul 2>&1
powercfg /change standby-timeout-ac 0 >nul 2>&1
powercfg /change standby-timeout-dc 0 >nul 2>&1
echo   OK: display and sleep timeouts set to Never (the app also keeps the screen on).

echo.
echo All done. Reboot to test:
echo   PC should log in by itself, then the kiosk should launch automatically.
echo   (Exit the kiosk any time with the hidden hotkey Ctrl+Alt+Shift+Q.)
echo   To undo both changes, run undo-kiosk.bat.
echo.
pause
