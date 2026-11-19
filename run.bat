@echo off
rem Double-click to play Polox.
setlocal
cd /d "%~dp0"
rem [PERSONAL_DATA] Saves, settings and keys live in PersonalData\ beside this file (scripts\core\personal_data.gd);
rem an old .polox-local\player or Documents\Polox folder is copied in once, never moved or deleted.
set "GODOT_DIR=%~dp0tools\godot"
set "GODOT=%GODOT_DIR%\Godot_v4.7.2-stable_win64.exe"
set "GODOT_CONSOLE=%GODOT_DIR%\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
  echo.
  echo  Godot 4.7.2 was not found in tools\godot\
  echo.
  echo  Easiest fix: double-click tools\get_godot.bat ^(downloads ~86 MB from GitHub^).
  echo  Or download Godot_v4.7.2-stable_win64.exe.zip yourself from
  echo  https://godotengine.org/download/archive/4.7.2-stable/
  echo  and unzip BOTH .exe files into tools\godot\
  echo.
  pause
  exit /b 1
)
echo Starting Polox...
rem Builds Godot's small import cache on first launch (and after updates).
"%GODOT_CONSOLE%" --headless --path . --import >nul 2>&1
start "" "%GODOT%" --path .
