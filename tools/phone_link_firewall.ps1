# Polox Phone Link - Windows Firewall helper (used by allow_phone_link.bat and the Doctor).
#   -Action check   read-only: Polox's rules, block rules for Polox's programs, network types, JSON with -Json
#   -Action plan    read-only: exactly what "allow" would change, step by step
#   -Action allow   (admin) 1. back up, then remove the Block rules for Polox's own programs only
#                           2. allow Polox's programs in on Polox's ports, on the network types in use now
#   -Action remove  (admin) Undo: delete the rules this helper added and put back the Block rules it removed
# Programs: tools\godot\Godot_v4.7.2-stable_win64.exe (+ _console.exe), tools\server\*.exe (Plan B, if present).
# Ports: 8765 8766 8767 (Phone Link) and 8080 8888 (Polox Ping).
# Tailscale Serve mode needs none of this: the phone reaches Tailscale, which talks to Polox on 127.0.0.1.
param(
  [ValidateSet('check', 'plan', 'allow', 'remove')] [string]$Action = 'check',
  [string]$Ports = '8765,8766,8767,8080,8888',
  [switch]$Json
)
$ErrorActionPreference = 'Stop'
$Group = 'Polox Phone Link'
$Root = Split-Path -Parent $PSScriptRoot
$PortList = @($Ports -split '[,; ]+' | Where-Object { $_ -match '^\d+$' })
# [PERSONAL_DATA] Polox run from this folder keeps its data in PersonalData\ (scripts\core\personal_data.gd).
$SaveRoot = Join-Path $Root 'PersonalData'
$Backup = Join-Path $SaveRoot 'phone\firewall_backup.json'
$Exes = @(
  (Join-Path $Root 'tools\godot\Godot_v4.7.2-stable_win64.exe'),
  (Join-Path $Root 'tools\godot\Godot_v4.7.2-stable_win64_console.exe')
) + @(Get-ChildItem -Path (Join-Path $Root 'tools\server') -Filter *.exe -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$Exes = @($Exes | Where-Object { $_ -and (Test-Path $_) })

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-InUseProfiles {
  $out = @()
  foreach ($p in (Get-NetConnectionProfile -ErrorAction SilentlyContinue)) {
    $c = [string]$p.NetworkCategory
    if ($c -eq 'DomainAuthenticated') { $c = 'Domain' }
    if ($out -notcontains $c) { $out += $c }
  }
  if ($out.Count -eq 0) { $out = @('Private') }
  return $out
}

function Test-PortCovered([string]$spec, [string]$port) {
  if (-not $spec -or $spec -eq 'Any') { return $true }
  foreach ($part in ($spec -split ',')) {
    $part = $part.Trim()
    if ($part -match '^(\d+)-(\d+)$') { if ([int]$port -ge [int]$Matches[1] -and [int]$port -le [int]$Matches[2]) { return $true } }
    elseif ($part -eq $port) { return $true }
  }
  return $false
}

function Get-PoloxRules {
  $found = @()
  $apps = @{}   # one bulk read (asking rule by rule takes minutes)
  foreach ($f in (Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue)) { $apps[[string]$f.InstanceID] = [string]$f.Program }
  foreach ($r in (Get-NetFirewallRule -Direction Inbound -ErrorAction SilentlyContinue)) {
    $prog = [string]$apps[[string]$r.InstanceID]
    $ours = ($r.Group -eq $Group)
    foreach ($e in $Exes) { if ($prog -and ($prog -ieq $e)) { $ours = $true } }
    if (-not $ours) { continue }
    $pf = $r | Get-NetFirewallPortFilter
    $found += [pscustomobject]@{
      name = [string]$r.Name; display = [string]$r.DisplayName; action = [string]$r.Action
      enabled = ([string]$r.Enabled -eq 'True'); profile = [string]$r.Profile; protocol = [string]$pf.Protocol
      port = [string]($pf.LocalPort -join ','); program = $prog; helper = ($r.Group -eq $Group); description = [string]$r.Description
    }
  }
  return $found
}

function Get-State {
  $rules = @(Get-PoloxRules)
  $inUse = @(Get-InUseProfiles)
  $blocking = @($rules | Where-Object { $_.enabled -and $_.action -eq 'Block' })
  $covered = $true
  $missing = @()
  foreach ($p in $inUse) {
    foreach ($port in $PortList) {
      $hit = $rules | Where-Object { $_.enabled -and $_.action -eq 'Allow' -and ($_.protocol -in @('TCP', 'Any')) -and (Test-PortCovered $_.port $port) -and ($_.profile -eq 'Any' -or $_.profile -match $p) }
      if (-not $hit) { $covered = $false; $missing += "$port ($p)" }
    }
  }
  $networks = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{ alias = [string]$_.InterfaceAlias; category = [string]$_.NetworkCategory } })
  return [pscustomobject]@{
    admin = (Test-Admin); port = $PortList[0]; ports = $PortList; exes = @($Exes); profiles_in_use = $inUse; networks = $networks
    rules = $rules; blocking = $blocking.Count; missing = $missing; allowed = $covered; ok = ($blocking.Count -eq 0 -and $covered)
    backup = (Test-Path $Backup)
  }
}

function Show-Plan($s) {
  Write-Host ""
  Write-Host " Polox's programs:"
  foreach ($e in $Exes) { Write-Host "   $e" }
  Write-Host " Polox's ports: $($PortList -join ', ')   Network types in use: $($s.profiles_in_use -join ', ')"
  Write-Host ""
  Write-Host " What 'allow' will do:"
  $step = 1
  foreach ($r in @($s.rules | Where-Object { $_.action -eq 'Block' -and -not $_.helper })) {
    Write-Host ("  {0}. REMOVE block rule '{1}' ({2}, {3}) for {4} (backed up first; Undo puts it back)" -f $step, $r.display, $r.protocol, $r.profile, (Split-Path -Leaf $r.program)); $step++
  }
  foreach ($r in @($s.rules | Where-Object { $_.helper })) {
    Write-Host ("  {0}. replace this helper's earlier rule '{1}' (port {2})" -f $step, $r.display, $r.port); $step++
  }
  foreach ($e in $Exes) {
    Write-Host ("  {0}. ADD: allow incoming TCP {1} for {2}, on {3} networks" -f $step, ($PortList -join ','), (Split-Path -Leaf $e), ($s.profiles_in_use -join '/')); $step++
  }
  Write-Host "  Nothing else is touched. Undo any time: allow_phone_link.bat remove"
}

if ($Action -in @('check', 'plan')) {
  $s = Get-State
  if ($Json) { $s | ConvertTo-Json -Depth 4 -Compress; exit 0 }
  Write-Host ""
  Write-Host "Networks in use: $(($s.networks | ForEach-Object { "$($_.alias) ($($_.category))" }) -join ', ')"
  if ($s.rules.Count -eq 0) { Write-Host "No firewall rules mention Polox's programs yet." }
  foreach ($r in $s.rules) { Write-Host ("  {0,-6} {1,-4} {2,-16} TCP {3,-22} {4}" -f $r.action, $(if ($r.enabled) { 'on' } else { 'off' }), $r.profile, $r.port, $r.display) }
  if ($s.blocking -gt 0) { Write-Host "-> $($s.blocking) BLOCK rule(s) stop phones from reaching Polox (Windows made them when its 'allow access?' prompt was dismissed). A Block rule beats any Allow rule." }
  if ($s.ok) { Write-Host "-> OK: phones on your $($s.profiles_in_use -join '/') network(s) may reach Polox on ports $($PortList -join ', ')." }
  elseif (-not $s.allowed) { Write-Host "-> Not allowed yet: $($s.missing -join ', ')." }
  if ($Action -eq 'plan') { Show-Plan $s }
  exit 0
}

if (-not (Test-Admin)) {
  Write-Host "This needs administrator rights (run allow_phone_link.bat; Windows will ask)."
  exit 2
}

if ($Action -eq 'remove') {
  $mine = @(Get-PoloxRules | Where-Object { $_.helper })
  $restored = 0
  foreach ($r in $mine) { Write-Host "Removing this helper's rule: $($r.display)"; Remove-NetFirewallRule -Name $r.name }
  if (Test-Path $Backup) {
    foreach ($b in @(Get-Content $Backup -Raw | ConvertFrom-Json)) {
      $restored++
      Write-Host "Putting back the block rule: $($b.display)"
      $args2 = @{ DisplayName = $b.display; Direction = 'Inbound'; Action = 'Block'; Program = $b.program; Profile = $b.profile }
      if ($b.protocol -and $b.protocol -ne 'Any') { $args2.Protocol = $b.protocol }
      if ($b.port -and $b.port -ne 'Any' -and $b.protocol -in @('TCP', 'UDP')) { $args2.LocalPort = @($b.port -split ',') }
      New-NetFirewallRule @args2 | Out-Null
    }
    Remove-Item $Backup
  }
  if ($mine.Count -eq 0 -and $restored -eq 0) { Write-Host "Nothing to undo: this helper hasn't changed anything." }
  exit 0
}

# allow
$s = Get-State
$profiles = @($s.profiles_in_use)
$blocks = @($s.rules | Where-Object { $_.action -eq 'Block' -and -not $_.helper })
if ($blocks.Count -gt 0) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Backup) | Out-Null
  $old = @()
  if (Test-Path $Backup) { $old = @(Get-Content $Backup -Raw | ConvertFrom-Json) }
  ($old + $blocks) | ConvertTo-Json -Depth 3 | Set-Content -Encoding utf8 $Backup
}
foreach ($r in $blocks) {
  Write-Host "Removing Windows' block rule: $($r.display) ($($r.protocol), $($r.profile))"
  Remove-NetFirewallRule -Name $r.name
}
foreach ($r in @($s.rules | Where-Object { $_.helper })) { Remove-NetFirewallRule -Name $r.name }
foreach ($e in $Exes) {
  $name = "Polox Phone Link ($(Split-Path -Leaf $e))"
  Write-Host "Allowing TCP $($PortList -join ',') for $(Split-Path -Leaf $e) on: $($profiles -join ', ')"
  New-NetFirewallRule -DisplayName $name -Group $Group -Direction Inbound -Action Allow -Protocol TCP -LocalPort $PortList -Program $e -Profile ($profiles -join ',') -Description 'Added by Polox allow_phone_link.bat; undo with allow_phone_link.bat remove' | Out-Null
}
Write-Host "Done. Undo any time with: allow_phone_link.bat remove"
exit 0
