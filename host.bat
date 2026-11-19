@echo off
rem Phone Link host: runs only the Polox server in a small window (address,
rem PIN, phone status), so your phone can play while the PC sits there. Close it to stop. No audio driver: it never plays a sound, and a Windows audio device change (another program taking the device, headphones) can't touch it.
setlocal
cd /d "%~dp0"
rem [PERSONAL_DATA] Saves, settings and keys live in PersonalData\ beside this file (scripts\core\personal_data.gd);
rem an old .polox-local\player or Documents\Polox folder is copied in once, never moved or deleted.
set "GODOT_CONSOLE=%~dp0tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT_CONSOLE%" (
  echo Godot 4.7.2 was not found in tools\godot\ - run tools\get_godot.bat first.
  pause
  exit /b 1
)
"%GODOT_CONSOLE%" --headless --path . --import >nul 2>&1
echo Starting Polox Phone Link (host only). Keep this window open while you play on your phone.
echo Only use this on your home network. Close the window to switch it off.
echo.
"%GODOT_CONSOLE%" --audio-driver Dummy --path . -- --host
pause
