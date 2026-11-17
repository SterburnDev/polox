@echo off
rem Builds the phone (Web) version of Polox into build\web\, which Phone Link
rem serves to your phone. Needs Polox's web engine (tools\build_engine.py web).
rem The Phone Link wizard (Settings > Phone Link) runs the same two steps.
setlocal
cd /d "%~dp0.."
set "GODOT=%CD%\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
  echo Godot 4.7.2 was not found - run tools\get_godot.bat first.
  pause
  exit /b 1
)
if not exist "tools\engine\web\web_nothreads_release.zip" (
  echo Polox's web engine is missing - run tools\pyenv\Scripts\python tools\build_engine.py web first.
  pause
  exit /b 1
)
if not exist "build\web" mkdir "build\web"
rem Godot must not import the build output as game assets.
if not exist "build\.gdignore" type nul > "build\.gdignore"
"%GODOT%" --headless --path . --import >nul 2>&1
"%GODOT%" --headless --path . --export-release "Web" "build/web/index.html"
if errorlevel 1 (
  echo Export failed.
  pause
  exit /b 1
)
rem A scratch save folder: the game's autoloads start with the script and must not open your worlds.
"%GODOT%" --headless --path . -s res://tools/web_postprocess.gd -- --save-root="%TEMP%\polox_web_postprocess"
if errorlevel 1 (
  echo The export worked, but the plain-HTTP step failed: Tailscale Serve ^(HTTPS^) still works.
  pause
  exit /b 1
)
echo Done: build\web\ is ready. Switch Phone Link on (Settings ^> Phone Link) and open it on your phone.
if "%1"=="" pause
