# termux-ssh-bridge

Give **Claude** (or any MCP-capable AI app) direct access to **Termux on your Android phone**, the same way you'd
connect it to a Linux server: through an SSH **MCP server**. Claude can then run commands on the phone, read
the output and move files, without you copy-pasting anything.

```
Claude ──(MCP: @fangjunjie/ssh-mcp-server)──ssh──► Termux on the phone (port 8022, same Wi-Fi)
```

- **Key-only login**: password login is turned off on the phone after setup.
- **One line on the phone**, one block in the Claude config.
- Tested on aarch64 Termux (Android 13) with the Claude desktop app on Windows.

---

## Setup (once per phone)

### 1. PC: create the key and get the install line

In PowerShell, from this repo's folder:

```powershell
.\pc\pair.ps1
```

This:
1. creates the PC's SSH key `~/.ssh/id_termux` (only the first time),
2. prints a one-line install command that contains the PC's **public** key, and copies it,
3. opens a **QR code** of that command in your browser, so you can get it onto the phone with the camera,
4. prints the Claude config block you'll need in step 3.

> If PowerShell blocks the script: `powershell -ExecutionPolicy Bypass -File .\pc\pair.ps1`

### 2. Phone: run the line in Termux

Scan the QR code (or send the line to yourself in a messenger), open **Termux**, paste it and press Enter.
It looks like this:

```bash
curl -fsSL https://raw.githubusercontent.com/ali934h/termux-ssh-bridge/main/termux/install.sh | bash -s -- 'ssh-ed25519 AAAA... termux-bridge@PC'
```

At the end it prints what you need for the Claude config:

```
  For the Claude MCP config:
    --host      192.168.1.50
    --port      8022
    --username  u0_a542
```

The IP is printed only if the Termux:API app is installed (see below). Otherwise, find it yourself:
**Settings → Connections → Wi-Fi → ⚙ next to your network → IP address** (the exact menu names vary by phone).
The user name is also shown by the `whoami` command in Termux.

### 3. PC: add the phone to Claude

Open the Claude config file:

- **Claude desktop app (Windows):** `%APPDATA%\Claude\claude_desktop_config.json`
  (or in Claude: **Settings → Developer → Edit Config**)

Inside `"mcpServers": { ... }`, add one block per phone. Use the IP and user name from step 2:

```json
"Phone-SSH": {
  "command": "npx",
  "args": [
    "-y", "@fangjunjie/ssh-mcp-server",
    "--host", "192.168.1.50",
    "--port", "8022",
    "--username", "u0_a542",
    "--privateKey", "C:\\Users\\YOU\\.ssh\\id_termux"
  ]
}
```

- Separate it from the block before it with a comma (`},`), and use `\\` in Windows paths.
- For a second phone, add another block with a different name (`Phone2-SSH`, ...) and its own IP and user name.
- **Fully quit Claude** (also from the system tray) and open it again. The phone's tools
  (run command, upload, download) now show up in every chat.

Test it: ask Claude *"run `uname -a` on my phone"*.

> Needs Node.js on the PC (for `npx`).

---

## When the router changes, or the phone gets a new IP

The IP is written directly in the Claude config, so if it changes, Claude can't reach the phone anymore.

1. Find the new IP on the phone (**Settings → Wi-Fi → your network → IP address**, or with Termux:API: `termux-wifi-connectioninfo`).
2. Replace the value after `"--host"` in `claude_desktop_config.json`.
3. Fully quit and reopen Claude.

**Tip:** in your router's settings, give the phone a **fixed IP** (often called *DHCP reservation*,
*Static lease* or *Address reservation*). Then its IP won't change until you replace the router.

---

## Keeping it reliable on Android

- **Settings → Apps → Termux → Battery → Unrestricted**, otherwise Android kills sshd when the screen is off.
- sshd starts **whenever Termux opens**. To have it start **after the phone reboots** too, install the
  **Termux:Boot** app (below) and open it once. The script has already placed `~/.termux/boot/start-sshd`.
- The phone and the PC must be on the **same Wi-Fi**.

## Optional add-on apps (install them yourself)

The script does **not** install these. Install them by hand if you want them:

| App | What it's for | Install |
|---|---|---|
| **Termux:API** | Lets commands reach phone features: battery, clipboard, notifications, Wi-Fi, location, camera... (`termux-battery-status`, `termux-clipboard-get`, ...) | 1) Install the app (link below) 2) In Termux: `pkg install termux-api` |
| **Termux:Boot** | Starts sshd automatically after the phone reboots, without opening Termux | Install the app (link below), then open it **once** |

**Where to download them:** from the **same place you installed Termux from**. Android refuses to install
an add-on whose signature doesn't match Termux, so don't mix sources (GitHub with F-Droid, or anything with Google Play).

| Termux installed from | Termux:API | Termux:Boot |
|---|---|---|
| **GitHub** (check: `echo $TERMUX_APK_RELEASE` prints `GITHUB`) | [github.com/termux/termux-api/releases](https://github.com/termux/termux-api/releases) → the `termux-api-app_v…+github.debug.apk` file | [github.com/termux/termux-boot/releases](https://github.com/termux/termux-boot/releases) → the `termux-boot-app_v…+github.debug.apk` file |
| **F-Droid** (`F_DROID`) | [f-droid.org/packages/com.termux.api](https://f-droid.org/packages/com.termux.api/) | [f-droid.org/packages/com.termux.boot](https://f-droid.org/packages/com.termux.boot/) |

Tips:
- Download the APK in the phone's browser, then open it from the **My Files / Downloads** app and tap **Install**
  (allow "Install unknown apps" for that app if Android asks).
- Test Termux:API: `termux-battery-status` should print JSON. If it hangs, the app is missing or comes from a different source than Termux.
- The first time each feature is used (location, camera, ...), Android asks for permission on the phone.

---

## What the scripts do

**`termux/install.sh`** (on the phone, safe to run again):
1. Checks it runs inside Termux.
2. Installs `openssh` if missing. No `pkg upgrade` unless the install fails (upgrades are slow).
3. Adds the PC's public key to `~/.ssh/authorized_keys` (skips it if already there).
4. Turns off password login once a key is installed (`sshd_config`), and tests the config.
5. Autostart: adds 3 lines to `~/.bashrc` (start sshd + wake-lock when Termux opens) and creates `~/.termux/boot/start-sshd` for Termux:Boot.
6. Starts sshd (or reloads it if it's already running).
7. Prints the phone's IP (if Termux:API is installed), the port and the user name for the Claude config.

Options (after the key): `--key-url URL` (download keys from a URL, e.g. `https://github.com/USER.keys`),
`--keep-password` (keep password login on), `--no-autostart`.

**`termux/uninstall.sh`**: undoes steps 4 and 5 and stops sshd. Keeps openssh and the authorized keys.

```bash
curl -fsSL https://raw.githubusercontent.com/ali934h/termux-ssh-bridge/main/termux/uninstall.sh | bash
```

**`pc/pair.ps1`** (on the PC): key, install line, QR code, config block (see step 1).

## Security

- Only someone with the private key on the PC (`~/.ssh/id_termux`) can log in. This repo contains no keys.
- The QR page is generated locally; only the QR drawing library is loaded from cdnjs. The QR contains only the command and your **public** key.
- Termux has no root access; Claude can do what Termux can do, nothing more.
- Don't share your `claude_desktop_config.json`: it often contains tokens of other MCP servers.
- To revoke one PC's access: delete its key line from `~/.ssh/authorized_keys` on the phone.

## Files

```
termux/install.sh     phone side (bash, Termux)
termux/uninstall.sh   undo the setup on the phone
pc/pair.ps1           PC side: key, install line, QR code, Claude config block
```
