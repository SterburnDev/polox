@echo off
rem Downloads portable Godot 4.7.2 into tools\godot\ (see get_godot.ps1).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0get_godot.ps1"
pause
