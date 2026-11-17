@echo off
rem Dev check: re-import, parse-check every script, then run the test suite.
rem Exit code 0 = all good. Usage: check.bat [test_name]   (e.g. check.bat test_ai)
setlocal EnableDelayedExpansion
cd /d "%~dp0"
set "ROOT=%~dp0"
set "GODOT=%ROOT%tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
  echo [check] Godot console binary not found: %GODOT%
  echo [check] Run tools\get_godot.bat first.
  exit /b 1
)
echo [check] Importing project...
"%GODOT%" --headless --path . --import >"%TEMP%\polox_import.txt" 2>&1
if !ERRORLEVEL! neq 0 (
  type "%TEMP%\polox_import.txt"
  echo [check] Import failed.
  exit /b 1
)
echo [check] Parse-checking scripts...
set FAILED=0
set COUNT=0
for /r "%ROOT%scripts" %%F in (*.gd) do call :checkone "%%F"
for /r "%ROOT%tests" %%F in (*.gd) do call :checkone "%%F"
if !FAILED! neq 0 (
  echo [check] !FAILED! of !COUNT! scripts failed to parse.
  exit /b 1
)
echo [check] !COUNT! scripts parse cleanly.
rem No personal details or keys anywhere in the checkout (names, addresses, machine names, user
rem folders, e-mail, keys): tools\release\make_public_source.py --check-checkout. It also reads a
rem private words list when there is one (POLOX_PRIVATE_WORDS, or .polox-local\notes\private_words.txt).
if not "%~1"=="" goto :tests
set "PY="
if exist "%ROOT%tools\pyenv\Scripts\python.exe" set "PY=%ROOT%tools\pyenv\Scripts\python.exe"
if not defined PY for /f "delims=" %%P in ('where python.exe 2^>nul ^| findstr /V /I /C:"WindowsApps"') do if not defined PY set "PY=%%P"
if not defined PY (
  echo [check] Privacy scan skipped: no Python found.
  goto :tests
)
echo [check] Looking for personal details and keys...
set "WORDS_FILE=%ROOT%.polox-local\notes\private_words.txt"
if defined POLOX_PRIVATE_WORDS set "WORDS_FILE=%POLOX_PRIVATE_WORDS%"
if exist "!WORDS_FILE!" (
  "!PY!" -B tools\release\make_public_source.py --check-checkout --private-words "!WORDS_FILE!" >"%TEMP%\polox_privacy.txt" 2>&1
) else (
  "!PY!" -B tools\release\make_public_source.py --check-checkout >"%TEMP%\polox_privacy.txt" 2>&1
)
set "PRIVACY_RC=!ERRORLEVEL!"
if !PRIVACY_RC! neq 0 (
  type "%TEMP%\polox_privacy.txt"
  echo [check] PERSONAL DETAILS OR KEYS FOUND: use the placeholders in CONTRIBUTING.md
  exit /b 1
)
for /f "delims=" %%L in ('findstr /B /C:"[privacy]" "%TEMP%\polox_privacy.txt"') do echo [check] %%L
:tests
echo [check] Running tests...
set "ONLY="
if not "%~1"=="" set "ONLY=-- --only=%~1"
"%GODOT%" --headless --path . --script res://tests/run_tests.gd %ONLY% >"%TEMP%\polox_tests.txt" 2>&1
set "TESTS_RC=!ERRORLEVEL!"
type "%TEMP%\polox_tests.txt"
rem A crash gives a negative exit code, which "if errorlevel 1" would miss.
if !TESTS_RC! neq 0 (
  echo [check] TESTS FAILED
  exit /b 1
)
rem A script error inside a test aborts that test silently: treat it as a failure
rem (except inside [expect-script-error] ... [/expect-script-error], where a test
rem causes one on purpose to prove it is contained).
powershell -NoProfile -Command "$t = Get-Content -Raw '%TEMP%\polox_tests.txt'; $t = [regex]::Replace($t, '(?s)\[expect-script-error\].*?\[/expect-script-error\]', ''); if ($t -match 'SCRIPT ERROR') { exit 0 } else { exit 1 }"
if not errorlevel 1 (
  echo [check] TESTS PRINTED SCRIPT ERRORS
  exit /b 1
)
rem Nothing may still be held when the engine closes: a node never freed, a resource never let go.
findstr /C:"ObjectDB instances were leaked" /C:"still in use at exit" "%TEMP%\polox_tests.txt" >nul
if not errorlevel 1 (
  echo [check] THE TEST RUN LEAKED OBJECTS AT EXIT
  exit /b 1
)
if not "%~1"=="" (
  echo [check] ALL GOOD
  exit /b 0
)
echo [check] Headless smoke run...
rem A fresh scratch root exercises first-run prompts on every check.
set "SMOKE_ROOT=%ROOT%tests\.tmp_save\smoke_!RANDOM!_!RANDOM!"
"%GODOT%" --headless --path . -- --save-root="!SMOKE_ROOT!" --drive=smoke >"%TEMP%\polox_smoke.txt" 2>&1
if !ERRORLEVEL! neq 0 (
  type "%TEMP%\polox_smoke.txt"
  echo [check] SMOKE RUN EXITED WITH AN ERROR
  exit /b 1
)
findstr /C:"[smoke] ok" "%TEMP%\polox_smoke.txt" >nul
if errorlevel 1 (
  type "%TEMP%\polox_smoke.txt"
  echo [check] SMOKE RUN FAILED
  exit /b 1
)
findstr /C:"SCRIPT ERROR" /C:"ERROR:" "%TEMP%\polox_smoke.txt" >nul
if not errorlevel 1 (
  type "%TEMP%\polox_smoke.txt"
  echo [check] SMOKE RUN PRINTED ERRORS
  exit /b 1
)
findstr /C:"ObjectDB instances were leaked" /C:"still in use at exit" "%TEMP%\polox_smoke.txt" >nul
if not errorlevel 1 (
  type "%TEMP%\polox_smoke.txt"
  echo [check] SMOKE RUN LEAKED OBJECTS AT EXIT
  exit /b 1
)
echo [check] Smoke run ok.
echo [check] ALL GOOD
exit /b 0

:checkone
set "ABS=%~1"
set "REL=!ABS:%ROOT%=!"
set "REL=!REL:\=/!"
set /a COUNT+=1
"%GODOT%" --headless --path . --check-only --script "res://!REL!" >"%TEMP%\polox_check.txt" 2>&1
if !ERRORLEVEL! equ 0 exit /b 0
rem --check-only can't see autoload singletons (they only exist once the game
rem runs), so "Identifier not found: <autoload>" is not a real failure here.
rem The same goes for "Failed to compile depended scripts" (a preloaded script
rem uses an autoload; its real errors show when that script is checked itself).
rem tests	est_00_compile.gd recompiles every script with autoloads loaded.
findstr /C:"SCRIPT ERROR" "%TEMP%\polox_check.txt" | findstr /V /C:"Identifier not found: SaveManager" /C:"Identifier not found: ChatLog" /C:"Identifier not found: AIClient" /C:"Identifier not found: GameState" /C:"Failed to compile depended scripts" >nul
if errorlevel 1 exit /b 0
echo   FAIL res://!REL!
findstr /C:"SCRIPT ERROR" /C:"at: GDScript" "%TEMP%\polox_check.txt"
set /a FAILED+=1
exit /b 0
