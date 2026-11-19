# Builds Polox for Android: build\android\polox.apk (arm64, signed with your own key), with Gradle, Polox's
# own engine (tools\engine\android, from tools\build_engine.py) and Polox's Android plugin (native\android).
# Needs the Android tools (tools\get_android_tools.ps1 -AcceptLicenses) and the engine build. The first
# build makes the signing key in tools\android\ (never committed, never printed): keep that folder, because
# Android only updates an installed app with an APK signed by the same key.
#   -Emulator   also include x86_64 (for the Android emulator; a bigger APK)
#   -NoPause    don't wait for a key press at the end (the in-game builder uses this)
#   -OutputDirectory   absolute path or a path relative to the project root
param([switch]$Emulator, [switch]$NoPause, [string]$OutputDirectory = '', [switch]$TestMobileCreation)
$ErrorActionPreference = 'Continue'   # native tools write progress to stderr; exit codes are checked instead
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root
function Done($code, $msg) {
  Write-Host $msg
  if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
  exit $code
}

$DefaultOutput = Join-Path $Root 'build\android'
$Out = $DefaultOutput
if ($OutputDirectory) {
  try {
    $provider = $null
    $drive = $null
    $Out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory, [ref]$provider, [ref]$drive)
    if ($provider.Name -ne 'FileSystem') { throw 'Choose a filesystem directory.' }
  } catch {
    Done 2 "Invalid -OutputDirectory. $($_.Exception.Message)"
  }
}
if ($TestMobileCreation -and $Out.TrimEnd([char[]]'\/') -eq $DefaultOutput) {
  Done 2 'A test drive requires a separate -OutputDirectory; never replace the downloadable app with a test build.'
}

$Godot = Join-Path $Root 'tools\godot\Godot_v4.7.2-stable_win64_console.exe'
$Jdk = Join-Path $Root 'tools\jdk17'
$Sdk = Join-Path $Root 'tools\android-sdk'
$BuildTools = Join-Path $Sdk 'build-tools\36.1.0'
$Engine = Join-Path $Root 'tools\engine\android'
$EngineLib = Join-Path $Engine 'godot-lib.template_release.aar'
$SourceZip = Join-Path $Engine 'android_source.zip'
if (-not (Test-Path $Godot)) { Done 2 'Godot 4.7.2 is missing: run tools\get_godot.bat first.' }
if (-not (Test-Path (Join-Path $Jdk 'bin\keytool.exe'))) { Done 2 'Java (JDK 17) is missing: run tools\get_android_tools.ps1 first.' }
if (-not (Test-Path (Join-Path $BuildTools 'apksigner.bat'))) { Done 2 'Android build-tools 36.1.0 are missing (see tools\build_engine.py).' }
if (-not ((Test-Path $EngineLib) -and (Test-Path $SourceZip))) { Done 2 "Polox's Android engine is missing: run tools\pyenv\Scripts\python tools\build_engine.py android first." }

# 1. The signing key (made once; the password is random and stays in tools\android\signing.json).
$KeyDir = Join-Path $Root 'tools\android'
$Keystore = Join-Path $KeyDir 'polox_release.keystore'
$Signing = Join-Path $KeyDir 'signing.json'
New-Item -ItemType Directory -Force -Path $KeyDir | Out-Null
if (-not (Test-Path $Keystore)) {
  $chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray()
  $bytes = New-Object byte[] 32
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $pass = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
  & (Join-Path $Jdk 'bin\keytool.exe') -genkeypair -keystore $Keystore -storetype PKCS12 -alias polox -keyalg RSA -keysize 2048 -validity 10000 -storepass $pass -keypass $pass -dname 'CN=Polox, OU=Polox on this PC, O=Polox' 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Keystore)) { Done 3 'Making the signing key failed (keytool).' }
  @{ alias = 'polox'; password = $pass; made = (Get-Date -Format s) } | ConvertTo-Json | Set-Content -Path $Signing -Encoding ascii
  Write-Host 'Made your signing key in tools\android\ (keep this folder: updates need the same key).'
}
$sig = Get-Content $Signing -Raw | ConvertFrom-Json

# Java, the SDK and Gradle's home (its download and libraries) for Gradle and for Godot, for this run only.
$env:JAVA_HOME = $Jdk
$env:ANDROID_HOME = $Sdk
$env:ANDROID_SDK_ROOT = $Sdk
$env:ANDROID_USER_HOME = Join-Path $Root 'tools\android-home'
$env:GRADLE_USER_HOME = Join-Path $Root 'tools\gradle-home'
# No Gradle daemon left behind: one would hold Godot's output pipe open and Godot would wait for it forever.
$env:GRADLE_OPTS = '-Dorg.gradle.daemon=false'
Add-Type -AssemblyName System.IO.Compression.FileSystem
function ZipEntryBytes($zipPath, $name) {
  $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
  try {
    $entry = $zip.GetEntry($name)
    if (-not $entry) { return $null }
    $s = $entry.Open(); $m = New-Object IO.MemoryStream; $s.CopyTo($m); $s.Dispose()
    return $m.ToArray()
  } finally { $zip.Dispose() }
}
function Sha256Hex([byte[]]$data) {
  $h = [Security.Cryptography.SHA256]::Create()
  try { return [BitConverter]::ToString($h.ComputeHash($data)).Replace('-', '').ToLowerInvariant() } finally { $h.Dispose() }
}

# 1b. Polox's Android plugin (native\android) -> addons\polox_android\bin\PoloxAndroid.aar, built with the
# Gradle wrapper from the engine's build template and compiled against the engine's own Java classes.
$Work = Join-Path $Root 'build\android-plugin'
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$GodotClasses = Join-Path $Work 'godot-classes.jar'
[IO.File]::WriteAllBytes($GodotClasses, (ZipEntryBytes $EngineLib 'classes.jar'))
$Wrapper = Join-Path $Work 'gradle'
$zip = [IO.Compression.ZipFile]::OpenRead($SourceZip)
try {
  foreach ($e in $zip.Entries) {
    if ($e.Name -and ($e.FullName -eq 'gradlew.bat' -or $e.FullName.StartsWith('gradle/wrapper/'))) {   # (files, not folder entries)
      $to = Join-Path $Wrapper $e.FullName
      New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
      [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $to, $true)
    }
  }
} finally { $zip.Dispose() }
Write-Host 'Building the Android plugin (Gradle)...'
$pluginLog = & cmd /c "`"$(Join-Path $Wrapper 'gradlew.bat')`" -p `"$(Join-Path $Root 'native\android')`" assembleRelease --no-daemon --quiet `"-PgodotClasses=$GodotClasses`"" 2>&1
if ($LASTEXITCODE -ne 0) { $pluginLog | Select-Object -Last 25 | ForEach-Object { Write-Host "  $_" }; Done 3 'Building the Android plugin failed (see above).' }
$Aar = Join-Path $Root 'native\android\build\outputs\aar\PoloxAndroid-release.aar'
if (-not (Test-Path $Aar)) { Done 3 'The Android plugin build made no AAR.' }
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'addons\polox_android\bin') | Out-Null
Copy-Item -Force $Aar (Join-Path $Root 'addons\polox_android\bin\PoloxAndroid.aar')

# 2. Export with Godot's Gradle build: --install-android-build-template puts the engine's template
# (export_presets.cfg: gradle_build/android_source_template) into android\build first. Godot takes the
# Java and SDK paths only from its editor settings, so for this one run the bundled Godot is
# "self-contained" (a _sc_ marker next to it): its settings come from tools\godot\editor_data\, written
# here, and your own Godot settings are left alone. The key comes from Godot's GODOT_ANDROID_KEYSTORE_*
# variables (only for this run).
$GodotDir = Split-Path $Godot -Parent
$EdData = Join-Path $GodotDir 'editor_data'
New-Item -ItemType Directory -Force -Path $EdData | Out-Null
$fwd = { param($p) $p.Replace('\', '/') }
@('[gd_resource type="EditorSettings" format=3]', '', '[resource]',
  ('export/android/java_sdk_path = "{0}"' -f (& $fwd $Jdk)),
  ('export/android/android_sdk_path = "{0}"' -f (& $fwd $Sdk))) | Set-Content -Path (Join-Path $EdData 'editor_settings-4.7.tres') -Encoding utf8
$Sc = Join-Path $GodotDir '_sc_'
New-Item -ItemType File -Force -Path $Sc | Out-Null
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $Keystore
$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $sig.alias
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $sig.password
New-Item -ItemType Directory -Force -Path $Out | Out-Null
if (-not (Test-Path (Join-Path $Root 'build\.gdignore'))) { New-Item -ItemType File -Path (Join-Path $Root 'build\.gdignore') | Out-Null }
$cfg = Join-Path $Root 'export_presets.cfg'
$TestArgs = 'command_line/extra_args="-- --save-root=/sdcard/Android/data/com.polox.app/files/mobile-qa --drive=mobile_creation --stay"'
# One Android export at a time: two overlapping test exports once "restored" the test command line as
# the preset itself (1.27.5), and the next downloadable APK started the test drive on launch.
$Lock = Join-Path $Root 'build\.export_android.lock'
try { $lockStream = [IO.File]::Open($Lock, 'OpenOrCreate', 'ReadWrite', 'None') } catch { Done 2 'Another Android export is running; wait for it to finish.' }
$cfgBefore = $null
$cfgNow = Get-Content $cfg -Raw
if ($cfgNow -match 'command_line/extra_args="[^"]*--drive=') {
  $lockStream.Dispose()
  Done 2 'export_presets.cfg still carries a test command line (an interrupted test export?): set command_line/extra_args="" first.'
}
if ($Emulator -or $TestMobileCreation) {
  $cfgBefore = $cfgNow
  $cfgTest = $cfgBefore
  if ($Emulator) { $cfgTest = $cfgTest -replace 'architectures/x86_64=false', 'architectures/x86_64=true' }
  if ($TestMobileCreation) { $cfgTest = $cfgTest.Replace('command_line/extra_args=""', $TestArgs) }
  [IO.File]::WriteAllText($cfg, $cfgTest, [Text.UTF8Encoding]::new($false))
}
$apk = Join-Path $Out 'polox.apk'
$tmp = Join-Path $Out 'polox_new.apk'
if (Test-Path $tmp) { Remove-Item $tmp -Force }
try {
  & $Godot --headless --audio-driver Dummy --path $Root --import 2>&1 | Out-Null
  $SaveRoot = Join-Path $Root 'tests\.tmp_save\android_export'
  & $Godot --headless --audio-driver Dummy --path $Root -- "--save-root=$SaveRoot" --write-build-id 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Done 4 'Could not stamp the Android build ID.' }
  Write-Host 'Exporting with Gradle (a few minutes)...'
  $log = & $Godot --headless --audio-driver Dummy --path $Root --install-android-build-template --export-release 'Android' $tmp 2>&1
  $code = $LASTEXITCODE
} finally {
  if ($null -ne $cfgBefore) { [IO.File]::WriteAllText($cfg, $cfgBefore, [Text.UTF8Encoding]::new($false)) }
  Remove-Item $Sc -Force -ErrorAction SilentlyContinue
  Remove-Item Env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD -ErrorAction SilentlyContinue
  $lockStream.Dispose()
}
$log | Set-Content -Path (Join-Path $Out 'export.log') -Encoding utf8
$log | Where-Object { $_ -match 'ERROR|error:|failed|FAILURE' } | Select-Object -First 12 | ForEach-Object { Write-Host "  $_" }
if ($code -ne 0 -or -not (Test-Path $tmp)) { Done 4 "The Android export failed (Godot exit $code; full log in $Out\export.log)." }

# 3. Check it: signed, the right package, version and permissions, the plugin and receiver merged in, and
# Polox's own engine inside (the same library the engine build made).
$verify = & cmd /c "`"$(Join-Path $BuildTools 'apksigner.bat')`" verify --print-certs `"$tmp`"" 2>&1
if ($LASTEXITCODE -ne 0) { Remove-Item $tmp -Force; Done 5 'The APK is not signed correctly (apksigner).' }
$badging = & (Join-Path $BuildTools 'aapt2.exe') dump badging $tmp 2>&1
$pkg = ($badging | Select-String "^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'").Matches
if ($pkg.Count -eq 0) { Remove-Item $tmp -Force; Done 5 'Could not read the APK (aapt2).' }
$perms = @($badging | Select-String "^uses-permission: name='([^']+)'" | ForEach-Object { $_.Matches[0].Groups[1].Value })
$tree = & (Join-Path $BuildTools 'aapt2.exe') dump xmltree --file AndroidManifest.xml $tmp 2>&1
if (-not ($tree | Select-String 'org.godotengine.plugin.v2.PoloxAndroid' -SimpleMatch)) { Remove-Item $tmp -Force; Done 5 'The APK lacks the PoloxAndroid plugin (manifest).' }
if (-not ($tree | Select-String 'org.polox.android.MissYouReceiver' -SimpleMatch)) { Remove-Item $tmp -Force; Done 5 'The APK lost the notification receiver (manifest).' }
$abis = $(if ($Emulator) { @('arm64-v8a', 'x86_64') } else { @('arm64-v8a') })
$engineSha = ''
foreach ($abi in $abis) {
  $inApk = ZipEntryBytes $tmp "lib/$abi/libgodot_android.so"
  $inLib = ZipEntryBytes $EngineLib "jni/$abi/libgodot_android.so"
  if ($null -eq $inApk -or $null -eq $inLib -or (Sha256Hex $inApk) -ne (Sha256Hex $inLib)) { Remove-Item $tmp -Force; Done 5 "The APK's $abi engine isn't Polox's engine build." }
  if ($abi -eq 'arm64-v8a') { $engineSha = Sha256Hex $inApk }
}
# The command line Godot packs into the APK (assets/_cl_): a test drive only in a test build.
$clBytes = ZipEntryBytes $tmp 'assets/_cl_'
$cl = $(if ($clBytes) { [Text.Encoding]::UTF8.GetString($clBytes) } else { '' })
if ($cl.Contains('--drive=') -ne [bool]$TestMobileCreation) { Remove-Item $tmp -Force; Done 5 'The APK has the wrong command line for this kind of build (a test drive in a downloadable APK, or none in a test one).' }
Move-Item -Force $tmp $apk
Remove-Item "$tmp.idsig" -Force -ErrorAction SilentlyContinue   # (a v4 signature file; a sideloaded APK doesn't need it)
$apkStream = [System.IO.File]::OpenRead($apk)
$apkHasher = [System.Security.Cryptography.SHA256]::Create()
try {
  $hash = [BitConverter]::ToString($apkHasher.ComputeHash($apkStream)).Replace('-', '').ToLowerInvariant()
} finally {
  $apkStream.Dispose()
  $apkHasher.Dispose()
}
if ($hash -notmatch '^[0-9a-f]{64}$') { Done 5 'Could not verify the built APK hash.' }
$cert = ($verify | Select-String 'certificate SHA-256 digest: ([0-9a-f]+)').Matches
$info = [ordered]@{
  package = $pkg[0].Groups[1].Value; version_code = [int]$pkg[0].Groups[2].Value; version = $pkg[0].Groups[3].Value
  size = (Get-Item $apk).Length; sha256 = $hash; cert_sha256 = $(if ($cert.Count) { $cert[0].Groups[1].Value } else { '' })
  permissions = $perms; abis = $abis; engine_sha256 = $engineSha; built = (Get-Date -Format s)
}
$info | ConvertTo-Json | Set-Content -Path (Join-Path $Out 'polox.json') -Encoding utf8
Done 0 ("Done: {0} ({1} {2}, {3:N1} MB)." -f $apk, $info.package, $info.version, ($info.size / 1MB))
