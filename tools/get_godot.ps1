# Downloads the portable Godot 4.7.2 engine (about 86 MB) from the official
# GitHub release, verifies its SHA-512 checksum, and unzips it into tools\godot\.
# No installer, no admin rights, no PATH or registry changes.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # the PS 5.1 progress bar makes downloads crawl
$version  = '4.7.2-stable'
$zipName  = "Godot_v${version}_win64.exe.zip"
$url      = "https://github.com/godotengine/godot/releases/download/$version/$zipName"
# From SHA512-SUMS.txt of the official 4.7.2-stable release.
$expected = '83decd58fdf67b9d657958a1ae6bf1929c20785315a81effe245874cdc57acb709bf868e00778a96984338c1b29dafdb453c6847747694621c6ecf5da2259993'
$dest     = Join-Path $PSScriptRoot 'godot'
$zipPath  = Join-Path $dest $zipName

New-Item -ItemType Directory -Force -Path $dest | Out-Null
if (Test-Path (Join-Path $dest "Godot_v${version}_win64.exe")) {
    Write-Host 'Godot 4.7.2 is already here. Nothing to do.'
    exit 0
}
Write-Host "Downloading Godot $version (about 86 MB)..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
Write-Host 'Checking the download is genuine (SHA-512)...'
$hash = (Get-FileHash -Path $zipPath -Algorithm SHA512).Hash.ToLower()
if ($hash -ne $expected) {
    Remove-Item $zipPath -Force
    throw 'Checksum mismatch: the download was damaged or tampered with, so it was deleted. Please try again.'
}
Expand-Archive -Path $zipPath -DestinationPath $dest -Force
Remove-Item $zipPath -Force
Write-Host 'Done! Double-click run.bat to play.'
