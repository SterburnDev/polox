@echo off
rem Polox Phone Link, Plan B: downloads the bundled web server (Caddy 2.11.4, official release,
rem SHA-256 checked) into tools\server\. Shows what it will download and asks first.
setlocal
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fetch_server.ps1" %*
echo.
pause
