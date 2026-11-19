@echo off
rem Builds Polox for Android into build\android\polox.apk (signed with this PC's own key in tools\android\).
rem Needs the Android tools (tools\get_android_tools.ps1 -AcceptLicenses) and Polox's engine
rem (tools\pyenv\Scripts\python tools\build_engine.py android). Add -Emulator for an x86_64 build too.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0export_android.ps1" %*
