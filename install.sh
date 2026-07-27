#!/usr/bin/env bash
# install.sh — run this ONCE per account (or after `git pull`) to wire the setup
# into your persistent home. After this, every future login on every machine
# provisions itself automatically.
#
# The only step that can ask for a password is creating /goinfre on a machine
# that has none (a VM, your own laptop). Say no and it uses /tmp instead.
#
#   ./install.sh                     asks where the big files should live
#   ./install.sh --store <path>      ... or say it up front (scripted installs)
#   ./install.sh --store auto        ... or explicitly keep goinfre/tmp
set -euo pipefail

STORE_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --store) STORE_ARG="${2:-}"; shift 2;;
    --store=*) STORE_ARG="${1#--store=}"; shift;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "install.sh: unknown option '$1'" >&2; exit 1;;
  esac
done
[ "$STORE_ARG" = auto ] && STORE_ARG=""

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
    --exclude '.git' --exclude 'extensions.txt' --exclude 'store-path' \
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

# --- where should the big, rebuildable things live? --------------------------
# Asked here, once, because this is the only decision the rest of the setup
# cannot make well on its own. devbox knows about /goinfre and /tmp; it cannot
# know you have a 256G disk mounted at /media/you/work.
#
# The answer is saved in $VS_SETUP_HOME (beside the setup, excluded from the
# rsync above), so it survives every later reinstall and follows you to the next
# machine. Empty answer = let devbox pick, which is the right answer on a school
# machine and stays the default.
#
# Skipped entirely when there is no terminal to ask at (CI, a scripted install),
# or when --store was passed, or when a choice was already made.
choose_store() {
  # shellcheck source=/dev/null
  . "$VS_SETUP_HOME/lib/common.sh"

  if [ -n "$STORE_ARG" ]; then
    store_set "$STORE_ARG" || {
      echo "    (keeping the automatic choice)"
      return 0
    }
    return 0
  fi
  [ -t 0 ] || return 0
  if [ -n "${VS_STORE_PREF:-}" ]; then
    echo "==> Store location: $VS_STORE_PREF (already chosen — 'devbox store --set' to change)"
    return 0
  fi

  cat <<'ASK'

==> Where should the big, rebuildable files go?
    (VSCode itself, its extensions, and docker's data — several GB, and never
     anything you cannot rebuild. Your settings and projects stay in your home.)

    Press ENTER to let devbox choose (/goinfre, else /tmp) — right for a school
    machine. Or type a path, e.g. an external disk: /media/you/work
ASK
  local ans why
  while :; do
    printf '    path [auto]: '
    read -r ans || return 0
    [ -n "$ans" ] || { echo "    Using the automatic choice."; return 0; }
    if why="$(store_check "${ans%/}")"; then
      store_set "$ans"
      return 0
    fi
    echo "    Cannot use that: $why"
    echo "    Try another path, or press ENTER for the automatic choice."
  done
}
choose_store

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
