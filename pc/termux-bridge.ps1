<#
.SYNOPSIS
  PC side of termux-ssh-bridge (Windows / PowerShell 5+).

.EXAMPLE
  .\termux-bridge.ps1 pair            # print (and copy) the one-line installer for a new phone
  .\termux-bridge.ps1 pair -Qr        # same, and open a QR code of it to scan with the phone
  .\termux-bridge.ps1 sync            # find phones on the Wi-Fi, register new ones, fix changed IPs
  .\termux-bridge.ps1 sync -Name tab  # give the next NEW phone the alias "tab"
  .\termux-bridge.ps1 list            # show registered phones
  .\termux-bridge.ps1 remove -Name tab

  After sync, use the alias:   ssh phone "uname -a"
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][ValidateSet('pair', 'sync', 'list', 'remove')][string]$Action = 'sync',
  [string]$Name,
  [string]$Subnet,            # e.g. 192.168.0  (default: auto-detect from physical adapters)
  [int]$Port = 8022,
  [int]$ScanTimeoutMs = 1500,
  [switch]$Qr
)
$ErrorActionPreference = 'Stop'

$Repo     = 'ali934h/termux-ssh-bridge'
$SshDir   = Join-Path $env:USERPROFILE '.ssh'
$KeyFile  = Join-Path $SshDir 'id_termux'
$Config   = Join-Path $SshDir 'config'
$Registry = Join-Path $SshDir 'termux-phones.json'
$Begin    = '# >>> termux-ssh-bridge >>>'
$End      = '# <<< termux-ssh-bridge <<<'
$Utf8     = New-Object System.Text.UTF8Encoding $false

function Get-PubKey {
  if (-not (Test-Path $SshDir)) { New-Item -ItemType Directory -Path $SshDir | Out-Null }
  if (-not (Test-Path $KeyFile)) {
    Write-Host "Creating SSH key $KeyFile"
    cmd /c "ssh-keygen -q -t ed25519 -f `"$KeyFile`" -N `"`" -C termux-bridge@$env:COMPUTERNAME" | Out-Null
    if (-not (Test-Path $KeyFile)) { throw 'ssh-keygen failed (is OpenSSH Client installed?)' }
  }
  (Get-Content "$KeyFile.pub" -Raw).Trim()
}

function Get-Phones {
  if (-not (Test-Path $Registry)) { return @() }
  $raw = [IO.File]::ReadAllText($Registry)
  if (-not $raw.Trim()) { return @() }
  $parsed = ConvertFrom-Json $raw
  foreach ($p in $parsed) { $p }   # emit items one by one (PS5 ConvertFrom-Json does not unroll arrays)
}

function Save-Phones($phones) {
  $json = ConvertTo-Json -InputObject @($phones) -Depth 4
  [IO.File]::WriteAllText($Registry, $json, $Utf8)
}

function Write-SshConfig($phones) {
  $lines = @($Begin, '# managed by termux-bridge.ps1 - do not edit inside this block')
  foreach ($p in $phones) {
    $lines += "Host $($p.name)"
    $lines += "    HostName $($p.ip)"
    $lines += "    Port $($p.port)"
    $lines += "    User $($p.user)"
    $lines += '    IdentityFile ~/.ssh/id_termux'
    $lines += '    IdentitiesOnly yes'
    $lines += "    HostKeyAlias termux-$($p.name)"   # host key checked by alias, so a new IP is fine
    $lines += '    StrictHostKeyChecking accept-new'
    $lines += '    ConnectTimeout 8'
    $lines += '    ServerAliveInterval 30'
  }
  $lines += $End

  $text = if (Test-Path $Config) { [IO.File]::ReadAllText($Config) } else { '' }
  $pattern = '(?s)' + [regex]::Escape($Begin) + '.*?' + [regex]::Escape($End) + '\r?\n?'
  $text = [regex]::Replace($text, $pattern, '').TrimEnd()

  foreach ($p in $phones) {   # warn about a hand-written block with the same alias (first match wins)
    if ($text -match "(?m)^\s*Host\s+(.*\s)?$([regex]::Escape($p.name))(\s|$)") {
      Write-Warning "~/.ssh/config already has its own 'Host $($p.name)' entry outside the managed block; remove it."
    }
  }
  $out = (($text, ($lines -join "`n")) | Where-Object { $_ }) -join "`n`n"
  [IO.File]::WriteAllText($Config, $out + "`n", $Utf8)
}

function Get-Subnets {
  if ($Subnet) { return @($Subnet.TrimEnd('.')) }
  $idx = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | ForEach-Object ifIndex)
  @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $idx -contains $_.InterfaceIndex -and $_.IPAddress -notmatch '^(127|169\.254)\.' } |
    ForEach-Object { ($_.IPAddress -split '\.')[0..2] -join '.' } | Select-Object -Unique)
}

function Find-OpenHosts([string[]]$prefixes) {
  $probes = New-Object System.Collections.ArrayList
  foreach ($pre in $prefixes) {
    foreach ($i in 1..254) {
      $c = New-Object System.Net.Sockets.TcpClient
      [void]$probes.Add([pscustomobject]@{ Ip = "$pre.$i"; Client = $c; Task = $c.ConnectAsync("$pre.$i", $Port) })
    }
  }
  Start-Sleep -Milliseconds $ScanTimeoutMs
  # Some routers / VPN adapters "accept" every TCP connection, so require a real SSH banner.
  $connected = @($probes | Where-Object { $_.Task.Status -eq 'RanToCompletion' })
  foreach ($p in $connected) {
    $buf = New-Object byte[] 64
    $p | Add-Member -NotePropertyName Buf -NotePropertyValue $buf
    $p | Add-Member -NotePropertyName Read -NotePropertyValue ($p.Client.GetStream().ReadAsync($buf, 0, 64))
  }
  if ($connected) { Start-Sleep -Milliseconds $ScanTimeoutMs }
  $open = @($connected | Where-Object {
      $_.Read.Status -eq 'RanToCompletion' -and $_.Read.Result -ge 4 -and
      [Text.Encoding]::ASCII.GetString($_.Buf, 0, 4) -eq 'SSH-' } | ForEach-Object Ip)
  foreach ($p in $probes) { try { $p.Client.Close() } catch {} }
  $open
}

function Test-Phone([string]$ip) {
  $ErrorActionPreference = 'Continue'   # PS5 would turn ssh's stderr into a terminating error
  # Termux ignores the user name, so any name works for the first contact.
  $remote = 'echo BRIDGE_OK; whoami; getprop ro.product.manufacturer; getprop ro.product.model; ssh-keygen -lf $PREFIX/etc/ssh/ssh_host_ed25519_key.pub | awk ''{print $2}'''
  $out = @(& ssh -i $KeyFile -p $Port -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=5 `
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o LogLevel=ERROR "termux@$ip" $remote 2>$null)
  if ($LASTEXITCODE -ne 0 -or $out.Count -lt 5 -or $out[0] -ne 'BRIDGE_OK') { return $null }
  [pscustomobject]@{ ip = $ip; user = $out[1].Trim(); model = ("$($out[2]) $($out[3])").Trim(); fingerprint = $out[4].Trim() }
}

function Get-NextName($phones) {
  if (-not ($phones | Where-Object name -eq 'phone')) { return 'phone' }
  $n = 2; while ($phones | Where-Object name -eq "phone$n") { $n++ }; "phone$n"
}

function Invoke-Sync {
  [void](Get-PubKey)
  $phones = New-Object System.Collections.ArrayList
  foreach ($p in Get-Phones) { [void]$phones.Add($p) }

  $subnets = @(Get-Subnets)
  if (-not $subnets) { throw 'No active Wi-Fi/Ethernet network found. Use -Subnet 192.168.x' }
  Write-Host "Scanning $(($subnets | ForEach-Object { "$_.0/24" }) -join ', ') for port $Port ..."
  $open = @(Find-OpenHosts $subnets)
  Write-Host "Port $Port open on: $(if ($open) { $open -join ', ' } else { 'nothing' })"

  $seen = @{}
  foreach ($ip in $open) {
    $f = Test-Phone $ip
    if (-not $f) { Write-Host "  $ip : not a paired Termux (key not accepted or not SSH)" -ForegroundColor DarkGray; continue }
    $seen[$f.fingerprint] = $true
    $known = $phones | Where-Object fingerprint -eq $f.fingerprint | Select-Object -First 1
    if ($known) {
      if ($known.ip -ne $f.ip) { Write-Host "  $($known.name): IP changed $($known.ip) -> $($f.ip)" -ForegroundColor Yellow }
      else { Write-Host "  $($known.name): OK at $($f.ip)" -ForegroundColor Green }
      $known.ip = $f.ip; $known.user = $f.user; $known.model = $f.model
      $known.lastSeen = (Get-Date).ToString('s')
    } else {
      $alias = if ($Name -and -not ($phones | Where-Object name -eq $Name)) { $Name } else { Get-NextName $phones }
      $Name = $null
      [void]$phones.Add([pscustomobject]@{ name = $alias; ip = $f.ip; port = $Port; user = $f.user; model = $f.model
          fingerprint = $f.fingerprint; lastSeen = (Get-Date).ToString('s') })
      Write-Host "  NEW phone '$alias' = $($f.model) at $($f.ip)" -ForegroundColor Cyan
    }
  }
  foreach ($p in $phones) {
    if (-not $seen[$p.fingerprint]) { Write-Host "  $($p.name): not found (offline, other network, or sshd not running) - keeping $($p.ip)" -ForegroundColor DarkYellow }
  }
  Save-Phones $phones
  Write-SshConfig $phones
  Show-Phones
}

function Show-Phones {
  $phones = @(Get-Phones)
  if (-not $phones) { Write-Host 'No phones registered yet. Run: .\termux-bridge.ps1 pair'; return }
  $phones | Format-Table name, ip, model, user, lastSeen -AutoSize | Out-Host
  Write-Host "Use:  ssh $($phones[0].name) `"uname -a`""
}

switch ($Action) {
  'pair' {
    $pub = Get-PubKey
    $cmd = "curl -fsSL https://raw.githubusercontent.com/$Repo/main/termux/install.sh | bash -s -- '$pub'"
    Write-Host "`nRun this in Termux on the new phone (same Wi-Fi as this PC):`n" -ForegroundColor Cyan
    Write-Host $cmd
    try { Set-Clipboard -Value $cmd; Write-Host "`n(copied to the PC clipboard)" -ForegroundColor DarkGray } catch {}
    if ($Qr) {
      Start-Process ('https://api.qrserver.com/v1/create-qr-code/?size=500x500&data=' + [uri]::EscapeDataString($cmd))
      Write-Host 'QR opened in the browser (contains only the command + your PUBLIC key).' -ForegroundColor DarkGray
    }
    Write-Host "`nThen run:  .\termux-bridge.ps1 sync`n" -ForegroundColor Cyan
  }
  'sync'   { Invoke-Sync }
  'list'   { Show-Phones }
  'remove' {
    if (-not $Name) { throw 'Use -Name <alias>' }
    $phones = @(Get-Phones | Where-Object name -ne $Name)
    Save-Phones $phones; Write-SshConfig $phones
    Write-Host "Removed '$Name' (to also revoke access, delete the PC key line in ~/.ssh/authorized_keys on that phone)."
  }
}
