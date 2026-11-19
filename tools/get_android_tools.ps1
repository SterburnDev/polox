# Polox for Android: the build tools, portable, inside tools\ (nothing installed system-wide).
#   1. Eclipse Temurin JDK 17 (Adoptium, SHA-256 checked)             -> tools\jdk17
#   2. Android SDK command-line tools (Google, SHA-256 checked)       -> tools\android-sdk
#   3. platform-tools (adb), build-tools 36.1.0, platform 36 and NDK 29.0.14206865 (+ the emulator and an
#      Android 15 image with -Emulator) through sdkmanager, which needs the Android SDK License Agreement
#      accepted (-AcceptLicenses).
# The engine itself is Polox's own build (tools\build_engine.py android), not Godot's ready-made templates.
# Android's own settings go to tools\android-home (not your user folder).
param([switch]$AcceptLicenses, [switch]$Emulator)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Tools = $PSScriptRoot
$Dl = Join-Path $Tools 'downloads'
New-Item -ItemType Directory -Force -Path $Dl | Out-Null

function Get-Checked($url, $file, $algo, $expected) {
  $path = Join-Path $Dl $file
  if (-not (Test-Path $path)) {
    Write-Host "Downloading $file ..."
    Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing
  }
  $got = (Get-FileHash -Path $path -Algorithm $algo).Hash.ToLower()
  if ($got -ne $expected) { Remove-Item $path -Force; throw "Checksum mismatch for $file (got $got): deleted." }
  Write-Host "  $file checksum OK"
  return $path
}

# 1. JDK 17
$jdk = Join-Path $Tools 'jdk17'
if (-not (Test-Path (Join-Path $jdk 'bin\java.exe'))) {
  $z = Get-Checked 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.20.1%2B1/OpenJDK17U-jdk_x64_windows_hotspot_17.0.20.1_1.zip' 'OpenJDK17U-jdk_x64_windows_hotspot_17.0.20.1_1.zip' 'SHA256' 'e53a79c3c3d86865bd7e787903884331068e71321714ffd44f145785affc7cb0'
  $tmp = Join-Path $Dl 'jdk_x'
  Expand-Archive -Path $z -DestinationPath $tmp -Force
  $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
  if (Test-Path $jdk) { Remove-Item -Recurse -Force $jdk }
  Move-Item $inner.FullName $jdk
  Remove-Item -Recurse -Force $tmp
  Remove-Item $z -Force
  Write-Host "  JDK in tools\jdk17"
}

# 2. Android command-line tools
$sdk = Join-Path $Tools 'android-sdk'
$cl = Join-Path $sdk 'cmdline-tools\latest'
if (-not (Test-Path (Join-Path $cl 'bin\sdkmanager.bat'))) {
  $z = Get-Checked 'https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip' 'commandlinetools-win-15859902_latest.zip' 'SHA256' '90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a'
  $tmp = Join-Path $Dl 'cl_x'
  Expand-Archive -Path $z -DestinationPath $tmp -Force
  New-Item -ItemType Directory -Force -Path (Split-Path $cl) | Out-Null
  if (Test-Path $cl) { Remove-Item -Recurse -Force $cl }
  Move-Item (Join-Path $tmp 'cmdline-tools') $cl
  Remove-Item -Recurse -Force $tmp
  Remove-Item $z -Force
  Write-Host "  command-line tools in tools\android-sdk"
}

# 3. SDK packages (needs the licence): tools\android_sdk_install.cmd answers the licence prompts of these packages only.
if (-not $AcceptLicenses) { Write-Host "Stopping before the SDK packages: run again with -AcceptLicenses once the Android SDK License Agreement is accepted."; exit 3 }
Write-Host "Installing the SDK packages (the Android SDK License Agreement was accepted by the user)..."
& cmd /c "`"$(Join-Path $Tools 'android_sdk_install.cmd')`" $(if ($Emulator) { 'emulator' } else { '' })"
if ($LASTEXITCODE -ne 0) { throw "The SDK package install failed ($LASTEXITCODE)." }
Write-Host "Done: adb at tools\android-sdk\platform-tools\adb.exe"
exit 0
