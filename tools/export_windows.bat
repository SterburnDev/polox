@echo off
rem Builds Polox for Windows into build\windows\: Polox.exe (the game in one file,
rem with Polox's icon and version) plus, when they're built, the phone version
rem (web\) and Polox for Android (polox.apk) that Phone Link serves. Copy the
rem folder anywhere and double-click Polox.exe; your worlds stay in Documents\Polox.
rem Needs Polox's Windows engine (tools\build_engine.py windows).
setlocal
cd /d "%~dp0.."
set "GODOT=%CD%\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
  echo Godot 4.7.2 was not found - run tools\get_godot.bat first.
  pause
  exit /b 1
)
if not exist "tools\engine\windows\windows_release_x86_64.exe" (
  echo Polox's Windows engine is missing - run tools\pyenv\Scripts\python tools\build_engine.py windows first.
  pause
  exit /b 1
)
if not exist "build\windows" mkdir "build\windows"
rem Godot must not import the build output as game assets.
if not exist "build\.gdignore" type nul > "build\.gdignore"
"%GODOT%" --headless --path . --import >nul 2>&1
rem The exe carries this source's build id, so it and its phone version agree.
if exist "build_id.txt" del "build_id.txt"
"%GODOT%" --headless --path . -- --save-root="%CD%\build\export_save" --write-build-id >nul 2>&1
if not exist "build_id.txt" (
  echo Could not write the build id.
  pause
  exit /b 1
)
"%GODOT%" --headless --path . --export-release "Windows" "build/windows/Polox.exe"
if errorlevel 1 (
  echo Export failed.
  pause
  exit /b 1
)
if exist "build\web\index.html" (
  robocopy "build\web" "build\windows\web" /MIR /NFL /NDL /NJH /NJS /NP >nul
  echo   + the phone version ^(web\^)
) else (
  echo   The phone version isn't built yet: Settings ^> Phone Link builds it, then run this again.
)
if exist "build\android\polox.apk" (
  copy /Y "build\android\polox.apk" "build\windows\polox.apk" >nul
  if exist "build\android\polox.json" copy /Y "build\android\polox.json" "build\windows\polox.json" >nul
  echo   + Polox for Android ^(polox.apk^)
)
echo Done: build\windows\Polox.exe is ready.
if "%1"=="" pause
