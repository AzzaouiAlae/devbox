#!/usr/bin/env bash
# install.sh — run this ONCE per account (or after `git pull`) to wire the setup
# into your persistent home. After this, every future login on every machine
# provisions itself automatically.
#
# The only step that can ask for a password is creating /goinfre on a machine
# that has none (a VM, your own laptop). Say no and it uses /tmp instead.
#
#   ./install.sh
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SRC/config.sh"

echo "==> Installing vscode-setup into $VS_SETUP_HOME"
mkdir -p "$VS_SETUP_HOME"

# Copy the repo into the persistent location (exclude VCS/junk). Keep the saved
# extension list, which lives here and must survive a reinstall.
#
# ui/bin and ui/obj are excluded for a reason worth stating: a local `dotnet
# build` leaves ~650M there. That is 13% of a school home, it is rebuildable, and
# it is built for whatever machine produced it. The SOURCE travels; the binary
# lives on the store like every other big thing here.
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete \
    --exclude '.git' --exclude 'extensions.txt' \
    --exclude 'ui/bin' --exclude 'ui/obj' \
    "$SRC"/ "$VS_SETUP_HOME"/
else
  cp -a "$SRC"/. "$VS_SETUP_HOME"/
  rm -rf "$VS_SETUP_HOME/.git" "$VS_SETUP_HOME/ui/bin" "$VS_SETUP_HOME/ui/obj"
fi

chmod +x "$VS_SETUP_HOME/ensure.sh" "$VS_SETUP_HOME/install.sh" \
         "$VS_SETUP_HOME"/bin/* 2>/dev/null || true

# --- wire the login hook into EVERY shell the machines actually use ----------
# School machines default to zsh, a personal Fedora/Rocky/Ubuntu box to bash.
# Hooking only one is why a machine can silently never repair itself.
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

wire_hook "$HOME/.bashrc"
wire_hook "$HOME/.zshrc"

echo "==> Running first provision now ..."
"$VS_SETUP_HOME/ensure.sh" --force --interactive || true

# --- the control panel -------------------------------------------------------
# Building it needs the .NET SDK; running it afterwards needs nothing. On a
# machine without an SDK we unpack the copy from your home cache instead, and
# only say something when there is neither. Never fatal: the CLI is the product,
# this is a window onto it.
echo "==> Control panel ..."
(
  # shellcheck source=/dev/null
  . "$VS_SETUP_HOME/lib/common.sh"; . "$VS_SETUP_HOME/lib/vscode.sh"; . "$VS_SETUP_HOME/lib/ui.sh"
  ensure_ui_shim
  # --refresh, not --build: compile only when there is no app yet, or when the
  # ui/ we just copied differs from what the existing app was built from. A
  # reinstall that changed nothing costs nothing.
  ensure_ui --refresh
) || echo "    (skipped — run 'make ui-docker' to build it in a container)"

STORE="$(cat "$VS_STORE_RECORD" 2>/dev/null || echo '?')"
cat <<EOF

Done. What happens from now on:
  * Every login (bash or zsh) runs a fast health check and repairs whatever this
    machine is missing: VSCode, extensions, your own docker, its storage.
  * Store (big, rebuilt per machine): $STORE
      docker data, VSCode itself, extensions, VSCode caches
  * Home (small, follows you): the VSCode download, your settings, your
    extension list, the 'code' command, and the control panel itself (35M).
  * Your docker: rootless, i.e. it runs as you. Socket always at $VS_SOCK_LINK
  * Helpers on PATH: devbox, setup-doctor, code, devbox-ui
  * The control panel: press ${VS_UI_HOTKEY:-<Control><Alt>d}, pick "devbox" in
    your app list, or run 'devbox ui' in any project

Next: open a project, run  'devbox init angular'  (or dotnet/cpp/base), then in
VSCode: "Dev Containers: Reopen in Container". Docker works inside the container.

Open a new terminal (or run: source ~/.bashrc) to pick up the PATH changes.
EOF
