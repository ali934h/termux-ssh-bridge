<#
.SYNOPSIS
  termux-ssh-bridge - PC side (Windows PowerShell 5+).
  1. Creates the PC's SSH key (~/.ssh/id_termux) if it doesn't exist yet.
  2. Prints the one-line installer for Termux (with this PC's public key) and copies it.
  3. Shows the same line as a QR code to scan with the phone camera.
  4. Prints the MCP config block to add to Claude.

.EXAMPLE
  .\pair.ps1
  .\pair.ps1 -NoQr
#>
param(
  [string]$KeyFile = (Join-Path $env:USERPROFILE '.ssh\id_termux'),
  [switch]$NoQr
)
$ErrorActionPreference = 'Stop'
$Repo = 'ali934h/termux-ssh-bridge'

# 1) Key
$sshDir = Split-Path $KeyFile
if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir | Out-Null }
if (-not (Test-Path $KeyFile)) {
  Write-Host "Creating SSH key: $KeyFile" -ForegroundColor Cyan
  cmd /c "ssh-keygen -q -t ed25519 -f `"$KeyFile`" -N `"`" -C termux-bridge@$env:COMPUTERNAME"
  if (-not (Test-Path $KeyFile)) { throw 'ssh-keygen failed. Is the Windows "OpenSSH Client" feature installed?' }
}
$pub = (Get-Content "$KeyFile.pub" -Raw).Trim()

# 2) One-liner
$cmd = "curl -fsSL https://raw.githubusercontent.com/$Repo/main/termux/install.sh | bash -s -- '$pub'"
Write-Host "`nRun this in Termux on the phone:`n" -ForegroundColor Cyan
Write-Host $cmd
try { Set-Clipboard -Value $cmd; Write-Host "`n(copied to the PC clipboard)" -ForegroundColor DarkGray } catch {}

# 3) QR code (local HTML page; the command never leaves this PC, only the QR library is loaded from cdnjs)
if (-not $NoQr) {
  $html = Join-Path $env:TEMP 'termux-pair.html'
  $js = ConvertTo-Json -InputObject $cmd
  $page = @"
<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Termux pairing</title>
<style>
 body{font-family:system-ui,sans-serif;max-width:640px;margin:2rem auto;padding:0 16px;background:#fff;color:#111}
 #qr{margin:1.25rem 0;display:inline-block;padding:16px;background:#fff;border:1px solid #ddd;border-radius:8px}
 code{display:block;word-break:break-all;background:#f3f3f3;padding:.75rem;border-radius:6px;font-size:13px}
 p{color:#444}
</style></head><body>
<h2>Scan with the phone, then paste into Termux</h2>
<p>Open the phone camera (or a QR app), copy the text, open Termux, long-press and Paste, then Enter.</p>
<div id="qr"></div>
<code id="c"></code>
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
<script>
 var t = $js;
 document.getElementById('c').textContent = t;
 new QRCode(document.getElementById('qr'), { text: t, width: 380, height: 380, correctLevel: QRCode.CorrectLevel.L });
</script>
</body></html>
"@
  [IO.File]::WriteAllText($html, $page, (New-Object System.Text.UTF8Encoding $false))
  Start-Process $html
  Write-Host "QR code opened in your browser ($html)." -ForegroundColor DarkGray
}

# 4) MCP config block
$keyJson = $KeyFile.Replace('\', '\\')
Write-Host @"

When the script on the phone finishes, it prints the phone's IP and user name.
Add this inside "mcpServers" in %APPDATA%\Claude\claude_desktop_config.json
(replace PHONE_IP and TERMUX_USER), then fully quit and reopen Claude:

    "Phone-SSH": {
      "command": "npx",
      "args": [
        "-y", "@fangjunjie/ssh-mcp-server",
        "--host", "PHONE_IP",
        "--port", "8022",
        "--username", "TERMUX_USER",
        "--privateKey", "$keyJson"
      ]
    }

"@ -ForegroundColor Cyan
