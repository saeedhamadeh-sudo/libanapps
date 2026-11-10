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
if not exist node_modules (
  echo  Installing - first time only...
  call npm install --omit=dev --no-audit --no-fund
)
:loop
node server.cjs
echo  Restarting in 5 seconds...
timeout /t 5 >nul
goto loop
