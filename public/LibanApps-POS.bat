@echo off
rem LibanApps POS - Chrome kiosk printing: receipts print silently on the Windows default printer
set "URL=https://libanapps.com"
set "PROFILE=%LOCALAPPDATA%\LibanAppsPOS"
set "CHROME=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" set "CHROME=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" set "CHROME=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" (
  echo Google Chrome is not installed.
  pause
  exit /b 1
)
start "" "%CHROME%" --kiosk-printing --user-data-dir="%PROFILE%" --new-window "%URL%"
