# shellcheck shell=bash
# lib/common.sh — logging, small helpers, and the storage picker.
# Sourced by ensure.sh, login.sh, and the bin/ tools. Never calls `exit`
# (so it is safe to source from an interactive shell).

# --- logging -----------------------------------------------------------------
# Colour only when attached to a terminal; always tee to the log file.
_vs_log_file() { echo "${VS_STATE_DIR:-$HOME/.local/state/vscode-setup}/setup.log"; }

_vs_ts() { date '+%Y-%m-%d %H:%M:%S'; }

_vs_emit() { # level color msg...
  local level="$1" color="$2"; shift 2
  local line="[$(_vs_ts)] $level: $*"
  mkdir -p "$(dirname "$(_vs_log_file)")" 2>/dev/null
  printf '%s\n' "$line" >> "$(_vs_log_file)" 2>/dev/null
  if [ -t 2 ]; then
    printf '\033[%sm%s\033[0m %s\n' "$color" "vscode-setup" "$*" >&2
  else
    printf 'vscode-setup: %s\n' "$*" >&2
  fi
}
info()  { _vs_emit INFO  "0;36" "$@"; }
ok()    { _vs_emit OK    "0;32" "$@"; }
warn()  { _vs_emit WARN  "0;33" "$@"; }
error() { _vs_emit ERROR "0;31" "$@"; }

# --- misc helpers ------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# fresh <file> <minutes> : true if <file> exists and is newer than <minutes>.
fresh() {
  local f="$1" mins="$2" now mtime
  [ -f "$f" ] || return 1
  now=$(date +%s) || return 1
  mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null) || return 1
  [ $(( (now - mtime) / 60 )) -lt "$mins" ]
}

# touch_marker <name> : record "we just did X" with current mtime.
touch_marker() { mkdir -p "$VS_STATE_DIR" 2>/dev/null; : > "$VS_STATE_DIR/$1"; }

# gnome_keybinding <slot> <name> <command> <binding> : a GNOME shortcut, best
# effort. Every shortcut needs its OWN slot number (custom0, custom1, ...) or the
# next one overwrites the last. Silently does nothing where there is no GNOME.
gnome_keybinding() {
  have gsettings || return 0
  local slot="$1" name="$2" cmd="$3" bind="$4"
  [ -n "$bind" ] || return 0
  local schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"
  local kpath="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom$slot/"
  gsettings set "$schema:$kpath" name    "$name" 2>/dev/null || return 0
  gsettings set "$schema:$kpath" command "$cmd"  2>/dev/null
  gsettings set "$schema:$kpath" binding "$bind" 2>/dev/null
  local list
  list="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null)"
  case "$list" in
    *"$kpath"*) : ;;
    "@as []"|"[]"|"") gsettings set org.gnome.settings-daemon.plugins.media-keys \
                        custom-keybindings "['$kpath']" 2>/dev/null ;;
    *) gsettings set org.gnome.settings-daemon.plugins.media-keys \
         custom-keybindings "${list%]}, '$kpath']" 2>/dev/null ;;
  esac
}

# fetch <url> <dest> : download with whatever tool the machine has.
fetch() {
  local url="$1" dest="$2"
  if have curl;   then curl -fL --retry 3 -o "$dest" "$url"
  elif have wget; then wget -q -O "$dest" "$url"
  else error "neither curl nor wget available"; return 1; fi
}

# arch_tag <flavour> : the machine's CPU written the way each project names it.
#   docker  -> x86_64 | aarch64      (docker static tarballs, compose assets)
#   go      -> amd64  | arm64        (buildx assets)
arch_tag() {
  local m; m="$(uname -m)"
  case "${1:-docker}" in
    go) case "$m" in x86_64|amd64) echo amd64;; aarch64|arm64) echo arm64;; *) echo "$m";; esac;;
    *)  case "$m" in amd64) echo x86_64;; arm64) echo aarch64;; *) echo "$m";; esac;;
  esac
}

# --- sudo (used for one thing only: creating /goinfre on a non-school box) ----
# sudo_ok         : we could use sudo without being asked for a password.
# sudo_maybe_ask  : true if sudo exists at all (a prompt is acceptable here).
sudo_ok()        { have sudo && sudo -n true 2>/dev/null; }
sudo_maybe_ask() { have sudo; }

# --- storage -----------------------------------------------------------------
# Free space in whole GB for the filesystem holding <dir> (0 on any error).
#
# Walks up to the nearest directory that exists, because the interesting question
# is almost always about a path we have not created yet: /goinfre/$USER right
# after it was cleaned out, or the folder you just picked on a new disk. df on a
# missing path answers nothing, and reporting that as "0G free" is worse than
# useless - it says "no room here" about a filesystem with 100G on it, and talks
# you out of the right choice.
avail_gb() {
  local d="$1" g
  [ -n "$d" ] || { echo 0; return; }
  while [ ! -d "$d" ] && [ "$d" != "/" ] && [ -n "$d" ]; do d="$(dirname "$d")"; done
  g=$(df -BG --output=avail "$d" 2>/dev/null | tail -1 | tr -dc '0-9')
  [ -n "$g" ] && echo "$g" || echo 0
}

# ensure_goinfre [--interactive] : make $VS_GOINFRE usable so every machine has
# the same layout. School machines already have it. A VM or a personal laptop
# does not, so we create it - that one step is the only place sudo appears, and
# without sudo we simply fall back to /tmp.
ensure_goinfre() {
  local interactive=0; [ "${1:-}" = "--interactive" ] && interactive=1
  [ "${VS_GOINFRE_CREATE:-1}" = 1 ] || return 1
  [ -n "$VS_GOINFRE" ] || return 1

  # Already fine (school machine, or we did this before).
  [ -d "$VS_GOINFRE" ] && [ -w "$VS_GOINFRE" ] && { _store_private "$VS_GOINFRE"; return 0; }
  # Parent is writable - which on a school box it is, /goinfre being 1777. No
  # sudo needed, and 700 from birth: this branch used to create the directory
  # with the default umask and never lock it down (only the sudo branch below
  # chmod'd), leaving every other account on the machine able to read whatever
  # landed there.
  if [ ! -e "$VS_GOINFRE" ] && mkdir -p -m 700 "$VS_GOINFRE" 2>/dev/null; then
    chmod 700 "$VS_GOINFRE" 2>/dev/null
    ok "created $VS_GOINFRE (yours only)"; return 0
  fi

  local why="missing"; [ -e "$VS_GOINFRE" ] && why="not writable by you"
  if sudo_ok; then
    :
  elif [ "$interactive" = 1 ] && sudo_maybe_ask; then
    info "$VS_GOINFRE is $why — asking sudo once to create it (only step that needs it)"
  else
    warn "$VS_GOINFRE is $why and sudo is not available now — using $VS_TMP instead"
    warn "run 'devbox goinfre' when you can type your password, to get the same layout as school"
    return 1
  fi

  if sudo mkdir -p "$VS_GOINFRE" && sudo chown "$(id -un):$(id -gn)" "$VS_GOINFRE"; then
    chmod 700 "$VS_GOINFRE" 2>/dev/null
    ok "$VS_GOINFRE is yours now (same layout as a school machine)"
    return 0
  fi
  warn "could not prepare $VS_GOINFRE — using $VS_TMP instead"
  return 1
}

# ensure_linger [--interactive] : without "linger", your own docker daemon is
# stopped the moment your last session ends, so a container you left running dies
# when you log out. Turning it on is the second (and last) one-time root step, and
# we ask for it in the same breath as /goinfre. Skipped silently when we cannot.
ensure_linger() {
  have loginctl || return 0
  case "$(loginctl show-user "$(id -un)" 2>/dev/null | grep -i '^Linger=')" in
    *=yes) return 0;;
  esac
  if sudo_ok || { [ "${1:-}" = "--interactive" ] && sudo_maybe_ask; }; then
    if sudo loginctl enable-linger "$(id -un)" 2>/dev/null; then
      ok "your services now keep running after you log out (linger on)"
      return 0
    fi
  fi
  info "containers stop when you log out (no linger). To change that: sudo loginctl enable-linger $(id -un)"
  return 1
}

# store_check <path> : can this path actually serve as a store? Echoes a reason
# on failure so the caller (CLI or GUI) can show the user WHY their disk was
# refused instead of silently ignoring it. Returns 0 when usable.
#
# The tests are in the order they fail in real life: a path on an unplugged
# external disk does not exist; a mounted-but-read-only disk exists and is not
# writable; a mount point whose disk has gone stale passes both and then fails
# the first real write, which is why we finish by actually creating a file.
store_check() {
  local p="$1" g
  [ -n "$p" ] || { echo "no path given"; return 1; }
  case "$p" in
    /*) ;;
    *) echo "must be an absolute path"; return 1;;
  esac
  # Refuse $HOME: the entire point of the store is to keep the big, rebuildable
  # things OFF a 5G quota. Silently honouring this would fill the home it exists
  # to protect.
  case "$p/" in
    "$HOME/"*) echo "that is inside your home ($HOME) — the store exists to keep big files OUT of it"; return 1;;
  esac
  # -m 700 at creation, not a chmod afterwards. On /tmp - shared with every other
  # account on the machine - the default umask makes it world-readable for the
  # moment between the two, and that moment is enough to matter. The app and this
  # setup are open source and hold no secrets; what goes in here alongside them is
  # your docker volumes and your project files, and those are yours.
  if [ ! -d "$p" ] && ! mkdir -p -m 700 "$p" 2>/dev/null; then
    echo "cannot create it (is the disk plugged in and mounted?)"; return 1
  fi
  [ -w "$p" ] || { echo "not writable by you"; return 1; }
  if ! ( : > "$p/.devbox-write-test" ) 2>/dev/null; then
    echo "the filesystem refused a write (read-only, or full)"; return 1
  fi
  rm -f "$p/.devbox-write-test" 2>/dev/null
  g=$(avail_gb "$p")
  if [ "$g" -lt "$VS_DOCKER_MIN_GB" ]; then
    echo "only ${g}G free, and a dev container wants ${VS_DOCKER_MIN_GB}G"; return 1
  fi
  return 0
}

# pick_store : echo the best root for the heavy, disposable tier.
# Your chosen path first (when it is there today), then goinfre (creating it if
# we may), then /tmp. If none meets the threshold, returns whichever has the
# most room so the setup still works.
pick_store() {
  local why
  # 1. what you asked for, if the disk is actually here.
  if [ -n "${VS_STORE_PREF:-}" ]; then
    if why="$(store_check "$VS_STORE_PREF")"; then
      echo "$VS_STORE_PREF"; return 0
    else
      warn "your chosen store $VS_STORE_PREF is unusable: $why"
      warn "falling back to goinfre/tmp for now — the choice is remembered, not discarded"
      warn "to point it somewhere else: devbox store --set <path>"
    fi
  fi

  # 2. the machine's own answer.
  ensure_goinfre "${1:-}" >/dev/null 2>&1 || true
  local best="" best_gb=-1 c g
  for c in "$VS_GOINFRE" "$VS_TMP"; do
    [ -n "$c" ] || continue
    # 700 from birth - see store_check. /tmp is shared with everyone on the box.
    mkdir -p -m 700 "$c" 2>/dev/null || continue
    [ -w "$c" ] || continue
    g=$(avail_gb "$c")
    if [ "$g" -ge "$VS_DOCKER_MIN_GB" ]; then echo "$c"; return 0; fi
    if [ "$g" -gt "$best_gb" ]; then best="$c"; best_gb="$g"; fi
  done
  if [ -n "$best" ]; then
    warn "no store has >= ${VS_DOCKER_MIN_GB}G free; using $best (${best_gb}G free)"
    warn "if you have a bigger disk, point devbox at it: devbox store --set <path>"
    echo "$best"; return 0
  fi
  return 1
}

# store_set <path> : remember <path> as where you want the store, in your home
# beside the rest of the setup so it survives a reinstall and follows you to the
# next machine. Validates first - a preference that cannot work is worse than
# none, because it silently degrades every later login.
store_set() {
  local p="$1" why
  p="${p%/}"
  case "$p" in "~"/*) p="$HOME/${p#\~/}";; esac
  if ! why="$(store_check "$p")"; then
    error "cannot use $p: $why"
    return 1
  fi
  mkdir -p "$(dirname "$VS_STORE_PREF_FILE")"
  printf '%s\n' "$p" > "$VS_STORE_PREF_FILE"
  VS_STORE_PREF="$p"; export VS_STORE_PREF
  ok "store location saved: $p ($(avail_gb "$p")G free)"
  return 0
}

# store_clear : go back to letting the machine decide (goinfre, else /tmp).
store_clear() {
  rm -f "$VS_STORE_PREF_FILE"
  VS_STORE_PREF=""; export VS_STORE_PREF
  ok "store location cleared — back to picking goinfre/tmp automatically"
}

# _store_private <dir> : nobody else's business.
#
# goinfre and /tmp are on a SHARED machine, and both default to world-readable.
# What we put there is not just caches: VSCode's workspaceStorage holds the state
# extensions keep per project, and its logs hold whatever they printed. Other
# people with an account on that machine could read all of it. One chmod on the
# root closes the whole tree, because they cannot traverse what they cannot enter.
# Best-effort: if we do not own the directory, leave it alone.
_store_private() {
  [ -d "$1" ] || return 0
  [ -O "$1" ] || return 0
  case "$(stat -c '%a' "$1" 2>/dev/null)" in
    700) return 0 ;;
    "")  return 0 ;;
  esac
  chmod 700 "$1" 2>/dev/null && info "locked $1 to you only (it was readable by other users)"
  return 0
}

# _store_warn_full <dir> : say so when the recorded store has filled up and some
# other candidate has real room. Rate-limited to once an hour, because store_dir
# runs from the `code` shim and from every shell that sources the hook, and a
# warning printed twenty times a day is a warning nobody reads.
_store_warn_full() {
  local cur="$1" gb alt alt_gb c
  gb=$(avail_gb "$cur")
  [ "$gb" -lt "$VS_DOCKER_MIN_GB" ] || return 0

  alt=""; alt_gb=$gb
  for c in "$VS_GOINFRE" "$VS_TMP"; do
    [ -n "$c" ] && [ "$c" != "$cur" ] && [ -d "$c" ] && [ -w "$c" ] || continue
    local g; g=$(avail_gb "$c")
    [ "$g" -gt "$alt_gb" ] && { alt="$c"; alt_gb=$g; }
  done

  fresh "$VS_STATE_DIR/store-full-warned" 60 && return 0
  touch_marker store-full-warned
  warn "the store $cur has only ${gb}G free — extension installs and container builds will fail here"
  if [ -n "$alt" ]; then
    warn "$alt has ${alt_gb}G free. To move: devbox store --repick   (or free space first: devbox gc)"
  else
    warn "free some up with: devbox gc  (then 'devbox gc --hard' if it is still tight)"
  fi
  return 0
}

# store_dir [--interactive] : the chosen store, remembered so every shell and
# every tool agrees on one answer. Re-picks when the recorded one has gone.
#
# "Has gone" used to be the only reason to re-pick, and that is not enough on a
# school machine. /goinfre is shared with every other student on the box: it can
# be 96% full with 47G of other people's directories while /tmp on the root
# filesystem has 100G+ free. Nothing you can delete fixes that - `devbox gc` only
# touches your own 5G - so a store pinned to goinfre stays broken forever, and
# the symptom is builds and extension installs failing for no stated reason.
#
# So a recorded store that has dropped below the floor is called out, with the
# alternative that would actually work. It is NOT switched silently: the store
# holds a running docker's data-root, and moving that out from under it mid
# session breaks more than it fixes. `devbox store --repick` is the deliberate
# version of that move.
store_dir() {
  local rec="$VS_STORE_RECORD" s
  if [ -r "$rec" ]; then
    s="$(cat "$rec" 2>/dev/null)"
    if [ -n "$s" ] && mkdir -p "$s" 2>/dev/null && [ -w "$s" ]; then
      # Your chosen disk is here but we are still running off the fallback -
      # this is the "I plugged the external drive back in" case. Say so; do not
      # switch underneath a running docker.
      if [ -n "${VS_STORE_PREF:-}" ] && [ "$VS_STORE_PREF" != "$s" ] \
         && store_check "$VS_STORE_PREF" >/dev/null 2>&1 \
         && ! fresh "$VS_STATE_DIR/store-pref-warned" 60; then
        touch_marker store-pref-warned
        warn "your chosen store $VS_STORE_PREF is available again, but we are using $s"
        warn "to move onto it: devbox store --repick"
      fi
      _store_private "$s"; _store_warn_full "$s"; echo "$s"; return 0
    fi
  fi
  s="$(pick_store "${1:-}")" || return 1
  _store_private "$s"
  mkdir -p "$VS_STATE_DIR" 2>/dev/null
  printf '%s\n' "$s" > "$rec"
  VS_STORE="$s"; export VS_STORE
  echo "$s"
}

# store_path <name> [--interactive] : $(store_dir)/<name>, created.
store_path() {
  local name="$1" s; s="$(store_dir "${2:-}")" || return 1
  mkdir -p "$s/$name" 2>/dev/null
  echo "$s/$name"
}
