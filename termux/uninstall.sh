#!/data/data/com.termux/files/usr/bin/bash
# termux-ssh-bridge — undo install.sh (keeps openssh and ~/.ssh/authorized_keys).
#   curl -fsSL https://raw.githubusercontent.com/ali934h/termux-ssh-bridge/main/termux/uninstall.sh | bash
main() {
  set -eu
  local CFG="$PREFIX/etc/ssh/sshd_config"
  sed -i '/^# >>> termux-ssh-bridge >>>$/,/^# <<< termux-ssh-bridge <<<$/d' "$HOME/.bashrc" 2>/dev/null || true
  rm -f "$HOME/.termux/boot/start-sshd"
  [ -f "$CFG" ] && sed -i '/^PasswordAuthentication no$/d;/^KbdInteractiveAuthentication no$/d;/^PubkeyAuthentication yes$/d' "$CFG"
  pkill -x sshd 2>/dev/null || true
  command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock || true
  echo "[+] Autostart removed, sshd stopped, password login restored."
  echo "    Authorized keys are still in ~/.ssh/authorized_keys (delete lines there to revoke a PC)."
}
main "$@"
