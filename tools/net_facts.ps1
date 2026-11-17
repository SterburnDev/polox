# Polox: facts about this PC's network, read-only (rung R0 of the connection ladder).
# Used by Polox Ping, the Doctor and phone_doctor.bat. Changes nothing.
#   -Ports  8765,8080,8888   ports to look up among the listening sockets
#   -Exes   "C:\...\a.exe;C:\...\b.exe"   programs whose firewall rules matter
# Prints one line of JSON.
param(
  [string]$Ports = '8765,8080,8888,8737',
  [string]$Exes = ''
)
$ErrorActionPreference = 'SilentlyContinue'
$portList = @($Ports -split ',' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
$exeList = @($Exes -split ';' | Where-Object { $_ -ne '' })
$out = [ordered]@{ ok = $true; errors = @() }

function Note($what) { $script:out.errors += [string]$what }

# Who am I (firewall rules can be limited to one Windows account).
try { $out.user_sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { $out.user_sid = '' }
$out.computer = $env:COMPUTERNAME
try { $os = Get-CimInstance Win32_OperatingSystem; $out.windows = "$($os.Caption) $($os.Version)" } catch { $out.windows = '' }

# R0.1 Listening sockets on the ports that matter, with the program that owns each.
$listen = @()
try {
  foreach ($c in (Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object { $portList -contains [int]$_.LocalPort })) {
    $path = ''; $name = ''
    try { $p = Get-Process -Id $c.OwningProcess -ErrorAction Stop; $name = $p.ProcessName; $path = [string]$p.Path } catch {}
    $listen += [ordered]@{ address = [string]$c.LocalAddress; port = [int]$c.LocalPort; pid = [int]$c.OwningProcess; process = $name; path = $path }
  }
} catch { Note "listening: $($_.Exception.Message)" }
$out.listening = $listen

# R0.2 Adapters, addresses, the default route and the network profile of each.
$routes = @{}
foreach ($r in (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)) {
  $routes[[int]$r.ifIndex] = [ordered]@{ gateway = [string]$r.NextHop; metric = [int]$r.RouteMetric + [int]$r.InterfaceMetric }
}
$profiles = @{}
foreach ($p in (Get-NetConnectionProfile -ErrorAction SilentlyContinue)) {
  $cat = [string]$p.NetworkCategory; if ($cat -eq 'DomainAuthenticated') { $cat = 'Domain' }
  $profiles[[int]$p.InterfaceIndex] = [ordered]@{ category = $cat; network = [string]$p.Name }
}
$adapters = @()
foreach ($a in (Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue)) {
  $ips = @(Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" })
  if ($ips.Count -eq 0 -and [string]$a.Status -ne 'Up') { continue }
  $pm = ''
  try { $pmo = Get-NetAdapterPowerManagement -Name $a.Name -ErrorAction Stop; $pm = [string]$pmo.AllowComputerToTurnOffDevice } catch {}
  $adapters += [ordered]@{
    name = [string]$a.Name; description = [string]$a.InterfaceDescription; status = [string]$a.Status; index = [int]$a.ifIndex
    ipv4 = $ips; default_route = $routes.ContainsKey([int]$a.ifIndex); gateway = $(if ($routes.ContainsKey([int]$a.ifIndex)) { $routes[[int]$a.ifIndex].gateway } else { '' })
    metric = $(if ($routes.ContainsKey([int]$a.ifIndex)) { $routes[[int]$a.ifIndex].metric } else { 0 })
    profile = $(if ($profiles.ContainsKey([int]$a.ifIndex)) { $profiles[[int]$a.ifIndex].category } else { '' })
    network = $(if ($profiles.ContainsKey([int]$a.ifIndex)) { $profiles[[int]$a.ifIndex].network } else { '' })
    power_off_allowed = $pm; virtual = [bool]$a.Virtual; hidden = [bool]$a.Hidden
  }
}
$out.adapters = $adapters
$vpn = @()
foreach ($v in (Get-VpnConnection -ErrorAction SilentlyContinue)) { $vpn += [ordered]@{ name = [string]$v.Name; status = [string]$v.ConnectionStatus } }
$out.vpn_connections = $vpn

# R0.3 Windows Firewall: the profiles, then rules for these programs and rules that block every program.
$fwp = @()
foreach ($p in (Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction SilentlyContinue)) {
  $fwp += [ordered]@{ name = [string]$p.Name; enabled = ([string]$p.Enabled -eq 'True'); default_inbound = [string]$p.DefaultInboundAction; allow_inbound_rules = ([string]$p.AllowInboundRules -ne 'False'); allow_local_rules = ([string]$p.AllowLocalFirewallRules -ne 'False') }
}
$out.firewall_profiles = $fwp
$rules = @()
try {
  $apps = @{}
  foreach ($f in (Get-NetFirewallApplicationFilter -ErrorAction Stop)) { $apps[[string]$f.InstanceID] = [string]$f.Program }
  foreach ($r in (Get-NetFirewallRule -Direction Inbound -ErrorAction Stop)) {
    $prog = [string]$apps[[string]$r.InstanceID]
    $mine = $false
    foreach ($e in $exeList) { if ($prog -and ($prog -ieq $e)) { $mine = $true } }
    $everyProgram = (($prog -eq '' -or $prog -eq 'Any') -and [string]$r.Action -eq 'Block' -and [string]$r.Enabled -eq 'True')
    if (-not ($mine -or $everyProgram -or [string]$r.DisplayName -match 'polox')) { continue }
    $pf = $r | Get-NetFirewallPortFilter
    $af = $r | Get-NetFirewallAddressFilter
    $sf = $r | Get-NetFirewallSecurityFilter
    $rules += [ordered]@{
      name = [string]$r.DisplayName; id = [string]$r.Name; action = [string]$r.Action; enabled = ([string]$r.Enabled -eq 'True'); profile = [string]$r.Profile
      protocol = [string]$pf.Protocol; port = [string]($pf.LocalPort -join ','); program = $(if ($prog) { $prog } else { 'Any' })
      remote = [string]($af.RemoteAddress -join ','); local_user = [string]$sf.LocalUser; source = [string]$r.PolicyStoreSourceType
      description = [string]$r.Description; for_this_program = $mine
    }
  }
} catch { Note "firewall rules: $($_.Exception.Message)"; $out.ok = $false }
$out.rules = $rules

# R0.4 Other security products (they may have their own firewall).
$sec = @()
foreach ($cls in @('FirewallProduct', 'AntiVirusProduct')) {
  foreach ($p in (Get-CimInstance -Namespace root/SecurityCenter2 -ClassName $cls -ErrorAction SilentlyContinue)) {
    $sec += [ordered]@{ kind = $cls; name = [string]$p.displayName; state = [int]$p.productState }
  }
}
$out.security_products = $sec

# R0.5 Sleep: minutes until the PC sleeps when idle (0 = never).
function SleepIndex($text, $label) {
  $m = [regex]::Match($text, "$label[^:]*:\s*0x([0-9a-fA-F]+)")
  if ($m.Success) { return [Convert]::ToInt32($m.Groups[1].Value, 16) } else { return -1 }
}
try {
  $q = (powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE) -join "`n"
  $out.sleep_ac_seconds = SleepIndex $q 'Current AC Power Setting Index'
  $out.sleep_dc_seconds = SleepIndex $q 'Current DC Power Setting Index'
} catch { $out.sleep_ac_seconds = -1; $out.sleep_dc_seconds = -1 }

$out | ConvertTo-Json -Depth 6 -Compress
