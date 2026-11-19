@echo off
rem Polox Ping: the smallest possible test server, to prove your phone can reach this PC at all.
rem No game, no pairing, no files. It listens on ports 8765, 8080 and 8888 (whichever are free)
rem and shows every address worth trying, big. Open one on your phone; the window lists every
rem contact. Close the window to stop it.  ping.bat --console  = no window, just this console.
setlocal
cd /d "%~dp0"
set "GODOT_CONSOLE=%~dp0tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT_CONSOLE%" (
  echo Godot 4.7.2 was not found in tools\godot\ - run tools\get_godot.bat first.
  pause
  exit /b 1
)
"%GODOT_CONSOLE%" --headless --path . --import >nul 2>&1
echo Starting Polox Ping. Keep this window open while you test with your phone.
echo.
if /i "%~1"=="--console" (
  "%GODOT_CONSOLE%" --headless --path . -- --ping 2>nul | findstr /B /C:"[ping]"
) else (
  "%GODOT_CONSOLE%" --audio-driver Dummy --path . -- --ping 2>nul | findstr /B /C:"[ping]"
)
pause
