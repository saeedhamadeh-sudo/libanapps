@echo off
chcp 65001 >nul
title LibanApps WhatsApp
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo  Node.js mesh mawjoud. Nazzlo men nodejs.org - LTS - w ba3dein shaghghel hal malaf marra tanye.
  start https://nodejs.org/en/download
  pause
  exit /b
)
if not exist "node_modules\@whiskeysockets\baileys\package.json" (
  echo  Installing - first time only...
  if exist node_modules rmdir /s /q node_modules
  if exist package-lock.json del package-lock.json
  call npm install --omit=dev --no-audit --no-fund
  if not exist "node_modules\@whiskeysockets\baileys\package.json" (
    echo.
    echo  Install failed. Check the internet connection, then run this file again.
    pause
    exit /b
  )
)
:loop
node server.cjs
echo  Restarting in 5 seconds...
timeout /t 5 >nul
goto loop
