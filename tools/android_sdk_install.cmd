@echo off
rem Installs the Android SDK packages Polox needs into tools\android-sdk (portable). sdkmanager shows the
rem licence of each of THESE packages and the "y" answers accept only those (run by
rem tools\get_android_tools.ps1 -AcceptLicenses, i.e. only after the user agreed to the Android SDK licence).
rem Pass "emulator" to add the emulator and an Android 15 system image (and make the polox_test device).
setlocal
set "T=%~dp0"
set "JAVA_HOME=%T%jdk17"
set "ANDROID_HOME=%T%android-sdk"
set "ANDROID_SDK_ROOT=%T%android-sdk"
set "ANDROID_USER_HOME=%T%android-home"
set "ANDROID_AVD_HOME=%T%android-home\avd"
set "SM=%T%android-sdk\cmdline-tools\latest\bin\sdkmanager.bat"
set "PKGS=platform-tools build-tools;36.1.0 platforms;android-36 ndk;29.0.14206865"
if /i "%~1"=="emulator" set "PKGS=%PKGS% emulator system-images;android-35;google_apis;x86_64"
set "YES=%TEMP%\polox_sdk_yes.txt"
(for /l %%i in (1,1,20) do @echo y) > "%YES%"
call "%SM%" "--sdk_root=%ANDROID_HOME%" %PKGS% < "%YES%"
if errorlevel 1 exit /b 1
if /i "%~1"=="emulator" (
  if not exist "%ANDROID_AVD_HOME%\polox_test.avd" (
    echo no| call "%T%android-sdk\cmdline-tools\latest\bin\avdmanager.bat" create avd -n polox_test -k "system-images;android-35;google_apis;x86_64" -d pixel_6 --force
  )
)
if not exist "%ANDROID_HOME%\platform-tools\adb.exe" exit /b 2
echo Android SDK packages ready.
exit /b 0
