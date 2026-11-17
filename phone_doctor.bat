@echo off
rem Phone Link Doctor: checks everything between this PC and your phone
rem (the phone version, Phone Link, every address, the firewall, Tailscale,
rem pairing) and says what to fix. Same checks as Settings > Phone Link > Doctor.
setlocal
cd /d "%~dp0"
set "GODOT=%~dp0tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
  echo Godot 4.7.2 was not found in tools\godot\ - run tools\get_godot.bat first.
  pause
  exit /b 1
)
"%GODOT%" --headless --path . -- --doctor 2>nul | findstr /B /C:"[doctor]"
echo.
echo The full report to paste when asking for help: Documents\Polox\phone\diagnostics.txt
echo (it has no keys, tokens, pairing codes or chats in it)
if "%1"=="" pause
