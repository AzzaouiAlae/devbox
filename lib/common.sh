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

# --- storage picker ----------------------------------------------------------
# Free space in whole GB for the filesystem holding <dir> (0 on any error).
avail_gb() {
  local g
  g=$(df -BG --output=avail "$1" 2>/dev/null | tail -1 | tr -dc '0-9')
  [ -n "$g" ] && echo "$g" || echo 0
}

# pick_store : echo the best storage root for heavy/ephemeral docker data.
# Prefers goinfre, falls back to /tmp when goinfre is missing or too full.
# If neither meets the threshold, returns whichever has the most space so the
# setup still works (just tighter). Prints nothing + returns 1 if none usable.
pick_store() {
  local best="" best_gb=-1 c g
  for c in "$VS_GOINFRE" "$VS_TMP"; do
    [ -n "$c" ] || continue
    mkdir -p "$c" 2>/dev/null || continue
    [ -w "$c" ] || continue
    g=$(avail_gb "$c")
    if [ "$g" -ge "$VS_DOCKER_MIN_GB" ]; then
      echo "$c"; return 0        # first location with enough room wins
    fi
    if [ "$g" -gt "$best_gb" ]; then best="$c"; best_gb="$g"; fi
  done
  if [ -n "$best" ]; then
    warn "no storage has >= ${VS_DOCKER_MIN_GB}G free; using $best (${best_gb}G free)"
    echo "$best"; return 0
  fi
  return 1
}
