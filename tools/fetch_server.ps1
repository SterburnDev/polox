# Polox Phone Link, Plan B: fetch the bundled web server (Caddy), pinned and checked.
# Downloads ONE file from Caddy's official GitHub release, checks its SHA-256 against the value
# recorded below, and keeps only caddy.exe and its licence in tools\server\. Never runs it.
# Polox starts it (Settings > Phone Link > Advanced > Server engine: Bundled) and stops it again.
param([switch]$Yes)
$ErrorActionPreference = 'Stop'
$Version = '2.11.4'
$Name = "caddy_${Version}_windows_amd64.zip"
$Url = "https://github.com/caddyserver/caddy/releases/download/v$Version/$Name"
$Size = 17559418
$Sha256 = '1708333f79e274c7697285afe6d592ab39314e0b131e9ec6bea08ad27df62ebf'   # GitHub's digest for this release asset
$Licence = 'Apache-2.0'
$Root = Split-Path -Parent $PSScriptRoot
$Dest = Join-Path $Root 'tools\server'

Write-Host ""
Write-Host " Polox Plan B: the bundled web server"
Write-Host " ===================================="
Write-Host "  File:    $Name"
Write-Host "  From:    $Url"
Write-Host ("  Size:    {0:N1} MB" -f ($Size / 1MB))
Write-Host "  SHA-256: $Sha256 (checked before anything is kept)"
Write-Host "  Licence: $Licence (Caddy, https://caddyserver.com)"
Write-Host "  Keeps:   tools\server\caddy.exe and tools\server\LICENSE (nothing else; nothing is run)"
Write-Host ""
if ((Test-Path (Join-Path $Dest 'caddy.exe')) -and (Test-Path (Join-Path $Dest 'VERSION.txt')) -and ((Get-Content (Join-Path $Dest 'VERSION.txt') -Raw) -match [regex]::Escape($Version))) {
  Write-Host " Already here: Caddy $Version. Nothing to do."
  exit 0
}
if (-not $Yes) {
  $ok = Read-Host " Type Y and press Enter to download it (anything else cancels)"
  if ($ok -ne 'Y' -and $ok -ne 'y') { Write-Host " Nothing was downloaded."; exit 1 }
}
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("polox_caddy_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
  $zip = Join-Path $tmp $Name
  Write-Host " Downloading..."
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $Url -OutFile $zip -UseBasicParsing
  $got = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
  if ($got -ne $Sha256) {
    Write-Host " CHECKSUM MISMATCH: got $got, expected $Sha256. Nothing was kept."
    exit 2
  }
  Write-Host " Checksum OK."
  $out = Join-Path $tmp 'x'
  Expand-Archive -Path $zip -DestinationPath $out -Force
  New-Item -ItemType Directory -Force -Path $Dest | Out-Null
  Copy-Item (Join-Path $out 'caddy.exe') (Join-Path $Dest 'caddy.exe') -Force
  if (Test-Path (Join-Path $out 'LICENSE')) { Copy-Item (Join-Path $out 'LICENSE') (Join-Path $Dest 'LICENSE') -Force }
  Set-Content -Encoding ascii -Path (Join-Path $Dest 'VERSION.txt') -Value "Caddy $Version ($Licence) from $Url sha256 $Sha256"
  Write-Host " Done: tools\server\caddy.exe (Caddy $Version)."
  Write-Host " Next: Polox > Settings > Phone Link > Advanced > Server engine: Bundled web server."
  Write-Host " If Windows Firewall needs it: allow_phone_link.bat (it now covers tools\server\caddy.exe too)."
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
exit 0
