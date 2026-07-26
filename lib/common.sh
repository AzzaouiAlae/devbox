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
avail_gb() {
  local g
  g=$(df -BG --output=avail "$1" 2>/dev/null | tail -1 | tr -dc '0-9')
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
  [ -d "$VS_GOINFRE" ] && [ -w "$VS_GOINFRE" ] && return 0
  # Parent is writable (rare, but then no sudo is needed at all).
  if [ ! -e "$VS_GOINFRE" ] && mkdir -p "$VS_GOINFRE" 2>/dev/null; then
    ok "created $VS_GOINFRE"; return 0
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

# pick_store : echo the best root for the heavy, disposable tier.
# Prefers goinfre (creating it if we may), falls back to /tmp. If neither meets
# the threshold, returns whichever has the most room so the setup still works.
pick_store() {
  ensure_goinfre "${1:-}" >/dev/null 2>&1 || true
  local best="" best_gb=-1 c g
  for c in "$VS_GOINFRE" "$VS_TMP"; do
    [ -n "$c" ] || continue
    mkdir -p "$c" 2>/dev/null || continue
    [ -w "$c" ] || continue
    g=$(avail_gb "$c")
    if [ "$g" -ge "$VS_DOCKER_MIN_GB" ]; then echo "$c"; return 0; fi
    if [ "$g" -gt "$best_gb" ]; then best="$c"; best_gb="$g"; fi
  done
  if [ -n "$best" ]; then
    warn "no store has >= ${VS_DOCKER_MIN_GB}G free; using $best (${best_gb}G free)"
    echo "$best"; return 0
  fi
  return 1
}

# store_dir [--interactive] : the chosen store, remembered so every shell and
# every tool agrees on one answer. Re-picks when the recorded one has gone.
store_dir() {
  local rec="$VS_STORE_RECORD" s
  if [ -r "$rec" ]; then
    s="$(cat "$rec" 2>/dev/null)"
    if [ -n "$s" ] && mkdir -p "$s" 2>/dev/null && [ -w "$s" ]; then echo "$s"; return 0; fi
  fi
  s="$(pick_store "${1:-}")" || return 1
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
