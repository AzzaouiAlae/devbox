#!/usr/bin/env bash
# install.sh — run this ONCE on a school machine (or after `git pull`) to wire
# the setup into your persistent home. After this, every future login on any
# machine provisions itself automatically. No root required.
#
#   ./install.sh
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SRC/config.sh"

echo "==> Installing vscode-setup into $VS_SETUP_HOME"
mkdir -p "$VS_SETUP_HOME"

# Copy the repo into the persistent location (exclude VCS/junk).
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete --exclude '.git' --exclude 'a' "$SRC"/ "$VS_SETUP_HOME"/
else
  cp -a "$SRC"/. "$VS_SETUP_HOME"/
  rm -rf "$VS_SETUP_HOME/.git"
fi

chmod +x "$VS_SETUP_HOME/ensure.sh" "$VS_SETUP_HOME/install.sh" \
         "$VS_SETUP_HOME"/bin/* 2>/dev/null || true

# --- wire the zsh login hook (idempotent, guarded block) ---------------------
HOOK_BEGIN="# >>> vscode-setup >>>"
HOOK_END="# <<< vscode-setup <<<"
HOOK_BODY='[ -f "$HOME/.config/vscode-setup/login.sh" ] && source "$HOME/.config/vscode-setup/login.sh"'

wire_hook() {
  local rc="$1"
  touch "$rc"
  if grep -qF "$HOOK_BEGIN" "$rc" 2>/dev/null; then
    echo "==> Hook already present in $rc"
    return
  fi
  {
    echo ""
    echo "$HOOK_BEGIN"
    echo "$HOOK_BODY"
    echo "$HOOK_END"
  } >> "$rc"
  echo "==> Added login hook to $rc"
}

wire_hook "$HOME/.zshrc"

echo "==> Running first provision now ..."
"$VS_SETUP_HOME/ensure.sh" || true

cat <<EOF

Done. What happens from now on:
  * Every login runs a fast health check and repairs anything the machine is
    missing (VSCode, docker storage on goinfre/tmp, Dev Containers extension).
  * VSCode is at:        $VS_HOME/bin/code   (persists, in your 5G home)
  * Docker data goes to: /goinfre/$USER/docker  (falls back to /tmp/$USER/docker)
  * Helpers on PATH:     devbox, setup-doctor

Next: open a project, run  'devbox init dotnet'  (or angular/cpp/base), then in
VSCode: "Dev Containers: Reopen in Container". Extensions install in the
container, not your home.

Open a new terminal (or run: source ~/.zshrc) to pick up the PATH changes.
EOF
