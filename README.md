# termux-ssh-bridge

Connect your phones' **Termux** to your **Windows PC** over SSH on the same Wi-Fi,
so that the PC (and Claude, which runs commands on the PC through Desktop Commander) can run commands directly on the phone and read their output.
No copy-pasting needed.

```
Claude ──► PC (Desktop Commander) ──ssh──► Termux on the phone (port 8022)
```

- **Key-only login**: password login is turned off after setup.
- **Router or IP changes are not a problem**: phones are identified by their unique *host key*, not their IP. One `sync` finds the new IPs.
- **Multiple phones**: each phone gets an alias (`phone`, `phone2`, ... or a name you choose).
- Tested on aarch64 Termux (Android 13) and Windows PowerShell 5.

---

## Adding a new phone (one time per phone)

**1. On the PC** (in this folder):

```powershell
.\pc\termux-bridge.ps1 pair
```

This prints a one-line command and copies it to the PC clipboard. To get it onto the phone,
send it to yourself in a messenger (for example, Telegram Saved Messages), or use `-Qr` to show it as a QR code you can scan with the phone camera:

```powershell
.\pc\termux-bridge.ps1 pair -Qr
```

**2. In Termux on the phone**, paste the command. It looks like this:

```bash
curl -fsSL https://raw.githubusercontent.com/ali934h/termux-ssh-bridge/main/termux/install.sh | bash -s -- 'ssh-ed25519 AAAA... termux-bridge@PC'
```

This installs `openssh`, authorizes the PC key, turns off password login,
sets sshd to start automatically when Termux opens, and starts it.

**3. On the PC:**

```powershell
.\pc\termux-bridge.ps1 sync
```

It scans the network, finds the phone, and builds the `phone` alias in `~/.ssh/config`. Done:

```powershell
ssh phone "uname -a"
ssh phone2 "termux-battery-status"
```

> To choose a name for the new phone: `.\pc\termux-bridge.ps1 sync -Name tablet`

---

## Telling your AI agent about the phones

There's no MCP server to install. An agent that can run commands on your PC (Claude with Desktop Commander,
Claude Code, Codex, ...) can use the phones through `ssh` - it just needs to be told. Run:

```powershell
.\pc\termux-bridge.ps1 agent
```

This prints short instructions with **your** phone aliases and copies them. Then either:
- paste them at the start of a chat, or
- save them once so every chat knows: as a **skill** in the Claude app, in your AI app's memory /
  custom instructions, or for Claude Code run `.\pc\termux-bridge.ps1 agent -Install`
  (saves `~/.claude/skills/termux-phone/SKILL.md`).

Run `agent` again after adding a phone. Agents working inside this repo also read [AGENTS.md](AGENTS.md).

## After a router change or a new IP

```powershell
.\pc\termux-bridge.ps1 sync
```

Same command. Each phone is identified by its host key fingerprint, and its new IP is written into the config.
Because of `HostKeyAlias`, SSH doesn't show a "host key changed" warning either.
If the subnet isn't detected (for example, on an unusual network): `sync -Subnet 192.168.0`

## Other commands

| Command | What it does |
|---|---|
| `.\pc\termux-bridge.ps1 list` | List registered phones |
| `.\pc\termux-bridge.ps1 remove -Name phone2` | Remove a phone from the PC |
| `.\pc\termux-bridge.ps1 agent [-Install]` | Instructions for an AI agent (see above) |
| `curl -fsSL https://raw.githubusercontent.com/ali934h/termux-ssh-bridge/main/termux/uninstall.sh \| bash` | Undo the setup on the phone |

## Keeping it reliable on Android

- **Settings → Apps → Termux → Battery → Unrestricted**, otherwise Android kills sshd when the screen is off.
- sshd starts **whenever Termux opens**. To have it start **after the phone reboots** too,
  install the **Termux:Boot** app (see the table below) and open it once. The script has already placed `~/.termux/boot/start-sshd`.

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
- `termux-open file.apk` only shows the installer when Termux is on screen; over SSH Android blocks it.
- Test Termux:API: `termux-battery-status` should print JSON. If it hangs, the app is missing or comes from a different source than Termux.
- The first time each feature is used (location, camera, ...), Android asks for permission on the phone.

## install.sh options

| Option | Effect |
|---|---|
| `'ssh-ed25519 ...'` | PC public key (you can pass several) |
| `--key-url URL` | Download keys from a URL (for example `https://github.com/USER.keys`) |
| `--keep-password` | Keep password login on |
| `--no-autostart` | Don't start sshd automatically |

## Security

- Only someone whose private key is on the PC (`~/.ssh/id_termux`) can log in. This repo contains no keys.
- Termux runs as a normal Android app user and has no root access; it can only reach files that Termux has access to.
- To revoke one PC's access: delete its key line from `~/.ssh/authorized_keys` on the phone.

## Files

```
termux/install.sh     phone side (bash, Termux)
termux/uninstall.sh   undo the setup on the phone
pc/termux-bridge.ps1  PC side (pair / sync / list / remove / agent)
AGENTS.md             notes for AI agents working with this repo
```

On the PC, the scripts use these files: `~/.ssh/id_termux` (key), `~/.ssh/config` (managed block), `~/.ssh/termux-phones.json` (phone list).
