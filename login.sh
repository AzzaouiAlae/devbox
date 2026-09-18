# shellcheck shell=bash
# login.sh — sourced from ~/.bashrc AND ~/.zshrc on every shell. MUST be fast and
# MUST NOT break the shell (no `set -e`, no `exit`, guard everything). Its job:
#   1. export PATH + DOCKER_HOST so `code` / `devbox` / `docker` just work
#   2. if the machine looks unprovisioned or stale, run ensure.sh
#
# The heavy check runs at most once per $VS_HEALTH_TTL_MIN, so extra terminals
# opened during a session stay instant.

: "${VS_SETUP_HOME:=$HOME/.config/vscode-setup}"
if [ -r "$VS_SETUP_HOME/config.sh" ]; then
  . "$VS_SETUP_HOME/config.sh"
  . "$VS_SETUP_HOME/lib/common.sh"

  # --- always: cheap PATH / env exports ---
  # $VS_BIN_DIR holds the `code` shim; $VS_SETUP_HOME/bin holds devbox + doctor.
  #
  # Move to the FRONT, every time — do not merely test "is it in PATH already".
  # Both dirs are ordinary ones a system may already have put on PATH behind the
  # machine's own: the desktop session and Debian's ~/.profile both append
  # ~/.local/bin at the END. A presence test passes there, the prepend is
  # skipped, and `code` keeps resolving to a root-installed /usr/bin/code
  # instead of our shim — while the GUI launcher, which uses an absolute path,
  # opens the right one. That split is confusing and hard to spot.
  #
  # Dropping the old copy before prepending keeps this idempotent: re-sourcing
  # cannot make PATH grow. Pure parameter expansion, no subshell and no fork,
  # because this runs on every single shell.
  _vs_path_prepend() {
    case ":$PATH:" in
      *":$1:"*)
        _vs_p=":$PATH:"
        while :; do
          case "$_vs_p" in
            *":$1:"*) _vs_p="${_vs_p%%":$1:"*}:${_vs_p#*":$1:"}";;
            *) break;;
          esac
        done
        # Strip the sentinel colons. A leftover empty field would mean "the
        # current directory" to every shell, which is not something to add to
        # someone's PATH by accident.
        _vs_p="${_vs_p#:}"; _vs_p="${_vs_p%:}"
        PATH="$_vs_p"
        unset _vs_p
        ;;
    esac
    # Guard the empty case: "$1:" would leave a trailing empty field, which
    # every shell reads as "the current directory".
    if [ -n "$PATH" ]; then PATH="$1:$PATH"; else PATH="$1"; fi
  }
  _vs_path_prepend "$VS_SETUP_HOME/bin"
  _vs_path_prepend "$VS_BIN_DIR"   # applied last, so the `code` shim wins
  unset -f _vs_path_prepend
  export PATH

  # Point the docker CLI at OUR daemon when that is how this machine is set up.
  if [ -r "$VS_STATE_DIR/docker-host" ]; then
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    DOCKER_HOST="$(cat "$VS_STATE_DIR/docker-host" 2>/dev/null)"
    export DOCKER_HOST
  fi
  # The stable socket path the dev-container templates mount.
  [ -S "$VS_SOCK_LINK" ] && export DEVBOX_DOCKER_SOCK="$VS_SOCK_LINK"

  # --- conditionally: provision this machine ---
  if ! fresh "$VS_STATE_DIR/last-ok" "${VS_HEALTH_TTL_MIN:-60}"; then
    if [ -t 1 ] && [ -z "${VS_SETUP_QUIET:-}" ]; then
      # Interactive first login on this machine: run in the foreground so docker
      # is ready before you need it (once per machine / TTL window).
      "$VS_SETUP_HOME/ensure.sh"
    else
      # Non-interactive shells: never block; provision detached.
      ( "$VS_SETUP_HOME/ensure.sh" >/dev/null 2>&1 & ) 2>/dev/null
    fi
    if [ -r "$VS_STATE_DIR/docker-host" ]; then
      DOCKER_HOST="$(cat "$VS_STATE_DIR/docker-host" 2>/dev/null)"; export DOCKER_HOST
    fi
    [ -S "$VS_SOCK_LINK" ] && export DEVBOX_DOCKER_SOCK="$VS_SOCK_LINK"
  fi
fi
