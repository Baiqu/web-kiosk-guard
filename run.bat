@echo off
REM Run Web Kiosk Guard directly with Python (development / no packaging).
REM Optionally pass a URL to override config.json:  run.bat https://your.site
setlocal
cd /d "%~dp0"
python src\main.py %*
