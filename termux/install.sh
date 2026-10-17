#!/data/data/com.termux/files/usr/bin/bash
# termux-ssh-bridge — make this Termux reachable from your PC over SSH (key-only).
#
# Usage (inside Termux):
#   curl -fsSL https://raw.githubusercontent.com/ali934h/termux-ssh-bridge/main/termux/install.sh \
#     | bash -s -- 'ssh-ed25519 AAAA... my-pc'
#
# Arguments:
#   'ssh-... KEY'        one or more PC public keys to authorize (quote each key)
#   --key-url URL        download public key(s) from URL instead (e.g. https://github.com/USER.keys)
#   --keep-password      keep password login enabled (default: disabled once a key is installed)
#   --no-autostart       don't start sshd automatically when Termux opens / on boot
#
# Safe to run again: it only adds what is missing.

main() {
  set -euo pipefail

  local MARK_BEGIN="# >>> termux-ssh-bridge >>>"
  local MARK_END="# <<< termux-ssh-bridge <<<"
  local CFG="${PREFIX:-}/etc/ssh/sshd_config"
  local AUTH="$HOME/.ssh/authorized_keys"

  say()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
  warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
  die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

  [[ "${PREFIX:-}" == *com.termux* ]] || die "Run this inside Termux."

  local -a KEYS=()
  local KEEP_PASSWORD=0 AUTOSTART=1 KEY_URL=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --keep-password) KEEP_PASSWORD=1 ;;
      --no-autostart)  AUTOSTART=0 ;;
      --key-url)       shift; KEY_URL="${1:-}"; [ -n "$KEY_URL" ] || die "--key-url needs a URL" ;;
      ssh-*|ecdsa-*|sk-*) KEYS+=("$1") ;;
      *) die "Unknown argument: $1" ;;
    esac
    shift
  done

  # 1) OpenSSH
  # No full upgrade by default (slow). Only if installing openssh fails or the
  # installed binaries don't run (old libraries), upgrade once and retry.
  export DEBIAN_FRONTEND=noninteractive
  if ! command -v sshd >/dev/null 2>&1; then
    say "Installing openssh..."
    if ! pkg install -y openssh </dev/null >/dev/null 2>&1 || ! ssh -V >/dev/null 2>&1; then
      warn "openssh install failed - upgrading packages once (this can take a while)..."
      pkg upgrade -y -o Dpkg::Options::=--force-confold </dev/null || true
      pkg install -y openssh </dev/null || die "Could not install openssh."
    fi
  fi
  ssh -V >/dev/null 2>&1 || die "ssh doesn't run. Try: pkg upgrade, then run this again."
  say "openssh: $(ssh -V 2>&1)"

  # 2) Authorized keys
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  touch "$AUTH"; chmod 600 "$AUTH"

  if [ -n "$KEY_URL" ]; then
    say "Downloading keys from $KEY_URL"
    while IFS= read -r line; do
      case "$line" in ssh-*|ecdsa-*|sk-*) KEYS+=("$line") ;; esac
    done < <(curl -fsSL "$KEY_URL" </dev/null)
  fi

  local k body
  for k in "${KEYS[@]}"; do
    body=$(awk '{print $2}' <<<"$k")
    [ -n "$body" ] || { warn "Skipping malformed key"; continue; }
    if grep -qF "$body" "$AUTH"; then
      say "Key already authorized: ${k:0:28}..."
    else
      printf '%s\n' "$k" >> "$AUTH"
      say "Key added: ${k:0:28}..."
    fi
  done

  local nkeys
  nkeys=$(grep -cE '^(ssh-|ecdsa-|sk-)' "$AUTH" || true)

  # 3) sshd config: key-only login once a key exists
  set_opt() {  # put "Key value" at the top of the file (first value wins in sshd)
    sed -i "/^[#[:space:]]*$1[[:space:]]/d" "$CFG"
    sed -i "1i $1 $2" "$CFG"
  }
  if [ "$nkeys" -gt 0 ] && [ "$KEEP_PASSWORD" -eq 0 ]; then
    set_opt PasswordAuthentication no
    set_opt KbdInteractiveAuthentication no
    set_opt PubkeyAuthentication yes
    say "Password login disabled (key-only)."
  else
    sed -i "/^PasswordAuthentication no$/d;/^KbdInteractiveAuthentication no$/d" "$CFG"
    if [ "$nkeys" -eq 0 ]; then
      warn "No key installed. Password login stays on; set one with: passwd"
    else
      warn "Password login kept on (--keep-password)."
    fi
  fi
  sshd -t || die "sshd config test failed: $CFG"

  # 4) Autostart
  if [ "$AUTOSTART" -eq 1 ]; then
    touch "$HOME/.bashrc"
    sed -i "/^$MARK_BEGIN\$/,/^$MARK_END\$/d" "$HOME/.bashrc"
    cat >> "$HOME/.bashrc" <<EOF
$MARK_BEGIN
# start the SSH server whenever Termux opens
pgrep -x sshd >/dev/null 2>&1 || sshd
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock
$MARK_END
EOF
    mkdir -p "$HOME/.termux/boot"
    cat > "$HOME/.termux/boot/start-sshd" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
# used by the Termux:Boot app (optional) to start sshd after a reboot
termux-wake-lock
sshd
EOF
    chmod +x "$HOME/.termux/boot/start-sshd"
    say "Autostart: ~/.bashrc + ~/.termux/boot/start-sshd"
  fi

  # 5) (Re)start sshd
  if pgrep -x sshd >/dev/null 2>&1; then
    pkill -HUP -x sshd && say "sshd reloaded."
  else
    sshd && say "sshd started."
  fi
  command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock || true

  # 6) Summary
  local fp
  fp=$(ssh-keygen -lf "$PREFIX/etc/ssh/ssh_host_ed25519_key.pub" 2>/dev/null | awk '{print $2}')
  echo
  echo "  Device : $(getprop ro.product.manufacturer 2>/dev/null) $(getprop ro.product.model 2>/dev/null) (Android $(getprop ro.build.version.release 2>/dev/null), $(uname -m))"
  echo "  User   : $(whoami)"
  echo "  Port   : 8022"
  echo "  HostKey: ${fp:-unknown}"
  echo "  Keys   : $nkeys authorized"
  echo
  # Optional add-on apps: only a hint, nothing is installed.
  local pkgs
  pkgs=$(cmd package list packages 2>/dev/null || true)
  if [ -n "$pkgs" ]; then
    grep -q 'com\.termux\.api$' <<<"$pkgs" \
      || warn "Optional: Termux:API app not installed (phone features). See README > Optional add-on apps."
    grep -q 'com\.termux\.boot$' <<<"$pkgs" \
      || warn "Optional: Termux:Boot app not installed - after a reboot, open Termux once to start sshd."
  fi
  say "Done. On the PC run:  .\\termux-bridge.ps1 sync"
  warn "Android: Settings > Apps > Termux > Battery > Unrestricted, so sshd isn't killed."
}

main "$@"
