@echo off
rem Phone Link, proven on this PC. Runs:
rem   0. builds the phone version (tools\export_web.bat), so the tests use the current one
rem   1. the Phone Link suites on 127.0.0.1 (server, PIN, launcher, Tailscale fixtures, pages, attacks, phone UX)
rem   2. end to end: the real server on a random port, reached on 127.0.0.1 AND every
rem      network address of this PC (home network, Tailscale), with the real phone
rem      version: files (bytes, SHA-256, MIME, gzip, Range), pairing, sync both ways,
rem      a deliberate conflict, the AI proxy (Mock), browser-like stress and attacks
rem   3. if Edge or Chrome is installed: a headless phone-size browser (InPrivate,
rem      throwaway profile) plays the real phone version over the network address
rem The end-to-end part listens on this PC's real network addresses for a minute.
rem Exit code 0 = everything passed.
setlocal EnableDelayedExpansion
cd /d "%~dp0"
set "GODOT=%~dp0tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
  echo [phone] Godot 4.7.2 was not found - run tools\get_godot.bat first.
  exit /b 1
)
echo [phone] 0/3 Building the phone version...
call tools\export_web.bat nopause >"%TEMP%\polox_phone0.txt" 2>&1
findstr /C:"[web]" "%TEMP%\polox_phone0.txt"
if errorlevel 1 (
  type "%TEMP%\polox_phone0.txt"
  echo [phone] The phone version didn't build ^(see above^).
  exit /b 1
)
echo [phone] 1/3 Phone Link suites (127.0.0.1)...
"%GODOT%" --headless --path . --script res://tests/run_tests.gd -- --only=test_phone,test_phone_link,test_phone_launcher,test_phone_ux,test_web_build >"%TEMP%\polox_phone1.txt" 2>&1
set "RC1=!ERRORLEVEL!"
findstr /R /C:"^  ok" /C:"^  FAIL" /C:"TESTS" /C:"FAILURE" /C:"^  - " "%TEMP%\polox_phone1.txt"
echo [phone] 2/3 + 3/3 End to end on this PC's real addresses, then a headless phone browser...
"%GODOT%" --headless --path . --script res://tests/run_tests.gd -- --dir=res://tests/e2e >"%TEMP%\polox_phone2.txt" 2>&1
set "RC2=!ERRORLEVEL!"
findstr /R /C:"^  ok" /C:"^  FAIL" /C:"TESTS" /C:"FAILURE" /C:"^  - " /C:"^    " "%TEMP%\polox_phone2.txt"
set "BAD=0"
if !RC1! neq 0 set "BAD=1"
if !RC2! neq 0 set "BAD=1"
rem Script errors anywhere fail the run (except ones a test causes on purpose, marked).
for %%F in ("%TEMP%\polox_phone1.txt" "%TEMP%\polox_phone2.txt") do (
  powershell -NoProfile -Command "$t = Get-Content -Raw '%%~F'; $t = [regex]::Replace($t, '(?s)\[expect-script-error\].*?\[/expect-script-error\]', ''); if ($t -match 'SCRIPT ERROR') { exit 0 } else { exit 1 }"
  if not errorlevel 1 (
    echo [phone] Script errors in %%~nxF:
    findstr /C:"SCRIPT ERROR" "%%~F"
    set "BAD=1"
  )
)
if !BAD! neq 0 (
  echo [phone] PHONE LINK CHECKS FAILED
  exit /b 1
)
echo [phone] ALL GOOD on this PC: Polox answers correctly on every address of this PC.
echo [phone] This does NOT prove your phone can reach it: traffic from the PC to itself skips the firewall,
echo [phone] the Wi-Fi and the router. Only the phone can show that: run ping.bat, open the address on the
echo [phone] phone and tap Run the full connection test (see docs\PHONE_TRIAGE.md).
exit /b 0
