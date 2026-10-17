# AGENTS.md - notes for AI agents

You are probably here because a user wants you to **reach their Android phone (Termux)** or to
**set this up** for them. This repo gives a Windows PC key-only SSH access to Termux on phones on the same Wi-Fi.
There is no MCP server: once set up, you reach a phone by running `ssh <alias> "<command>"` on the PC
with whatever command tool you already have (terminal, shell, Desktop Commander...).

## 1. Is it already set up?
Run on the PC:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File pc\termux-bridge.ps1 list
```
- Phones listed -> try `ssh <alias> "echo ok"`. If it fails, run `... termux-bridge.ps1 sync` (fixes changed IPs).
  Still failing -> ask the user to open Termux on the phone (sshd starts when Termux opens) and check they are on the same Wi-Fi.
- Nothing listed -> go to 2.

## 2. Set up a new phone
1. PC: `... termux-bridge.ps1 pair` -> prints a one-line `curl ... | bash -s -- 'ssh-ed25519 ...'` command.
2. **The user** pastes that line into Termux on the phone (you can't type on the phone). They can send it to
   themselves via a messenger, or use `pair -Qr` and scan the QR code.
3. PC: `... termux-bridge.ps1 sync` -> registers the phone as `phone`, `phone2`, ... (`-Name x` to choose).
4. Optional apps (Termux:API, Termux:Boot): the user installs them by hand - see README "Optional add-on apps".
   Don't install APKs for them; Android blocks installer screens launched over SSH anyway.

## 3. Remember it for next time
`... termux-bridge.ps1 agent` prints instructions with the user's own aliases (and copies them).
Suggest the user saves them as a skill / memory / custom instructions in their AI app.
`agent -Install` saves them as a Claude Code skill in `~/.claude/skills/termux-phone/`.

## Working on a phone - rules of thumb
- Termux shell: bash, no root, `$PREFIX=/data/data/com.termux/files/usr`, packages via `pkg install -y <name>`
  (don't run `pkg upgrade` unless something is broken - it's slow). Ask before large installs.
- Windows PowerShell 5 mangles quotes in long native arguments: write multi-line scripts to a file and run
  `(Get-Content f.sh -Raw) -replace "`r","" | ssh phone bash`.
- Termux:API commands (`termux-battery-status`, ...) hang if the Termux:API app is missing: use `timeout 15`.
- Never re-enable password login or print private keys. The PC key is `~/.ssh/id_termux`.

## Repo layout
| Path | Role |
|---|---|
| `termux/install.sh` | Runs on the phone (via the curl one-liner). Idempotent. |
| `termux/uninstall.sh` | Undo on the phone. |
| `pc/termux-bridge.ps1` | PC side: `pair`, `sync`, `list`, `remove`, `agent`. |

PC state: `~/.ssh/id_termux` (key), managed block in `~/.ssh/config`, `~/.ssh/termux-phones.json` (registry, matched by host-key fingerprint).
Keep `*.sh` files LF (see `.gitattributes`); keep the PowerShell script ASCII and PowerShell 5 compatible.
