@echo off
cd /d "%~dp0"
set S=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\LibanApps-WhatsApp.vbs
echo Set W = CreateObject("WScript.Shell") > "%S%"
echo W.Run "cmd /c ""%~dp0START-WHATSAPP.bat""", 7, False >> "%S%"
echo  Done - it will start automatically with Windows.
pause
