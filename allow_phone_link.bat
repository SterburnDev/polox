@echo off
rem Polox Phone Link - Windows Firewall helper. Optional, explained, never silent, with an Undo.
rem   allow_phone_link.bat          show what it would change, then (after you type Y) change it
rem   allow_phone_link.bat check    only show what Windows allows now
rem   allow_phone_link.bat remove   Undo: remove this helper's rules, put back the block rules it removed
rem It only ever touches rules for Polox's own programs (tools\godot\*.exe, tools\server\*.exe).
rem Tailscale Serve works without any firewall change.
setlocal
cd /d "%~dp0"
set "ACTION=%~1"
rem (older versions took a port first: allow_phone_link.bat 8737 allow)
echo %ACTION%| findstr /R "^[0-9][0-9]*$" >nul && set "ACTION=%~2"
if "%ACTION%"=="" set "ACTION=allow"
set "PS=powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\phone_link_firewall.ps1""

echo.
echo  Polox Phone Link - Windows Firewall helper
echo  ==========================================
if /i "%ACTION%"=="check" (
  %PS% -Action check
  echo.
  pause
  exit /b 0
)

net session >nul 2>&1
if errorlevel 1 (
  %PS% -Action plan
  echo.
  echo  Changing firewall rules needs administrator rights. Windows will ask you now.
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%ACTION%' -Verb RunAs"
  exit /b 0
)

if /i "%ACTION%"=="remove" (
  echo  Undo: this removes the rules this helper added ^(group "Polox Phone Link"^) and puts back
  echo  any block rules it removed earlier. Nothing else is touched.
) else (
  %PS% -Action plan
  echo.
  echo  Polox itself still refuses anything that isn't your home network or Tailscale,
  echo  and every phone still needs the PIN shown on the PC.
  echo  Tip: if your home network shows as "Public", you can mark it "Private" in
  echo  Windows Settings ^> Network ^& internet ^> your connection ^> Network profile type.
)
echo.
set "OK="
set /p OK=Type Y and press Enter to go ahead (anything else cancels): 
if /i not "%OK%"=="Y" (
  echo Nothing was changed.
  pause
  exit /b 0
)
%PS% -Action %ACTION%
echo.
%PS% -Action check
pause
