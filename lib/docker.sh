# shellcheck shell=bash
# lib/docker.sh — give this developer their OWN docker, on every machine.
#
# Two invariants:
#   1. The daemon runs as YOU (rootless), not as root. Then "root" inside a
#      container IS you outside it, so files a container writes into your project
#      stay yours, and handing the socket to a dev container hands over your own
#      daemon instead of root's.
#   2. Its data lives on goinfre/tmp, never under $HOME (5G quota).
#
# The socket always shows up at one stable path ($VS_SOCK_LINK), which is what
# the dev-container templates mount. That is why the same devcontainer.json
# works on a school machine, a VM and a personal laptop with no edits.

docker_running()    { docker info >/dev/null 2>&1; }
docker_is_rootless(){ docker info -f '{{println .SecurityOptions}}' 2>/dev/null | grep -qi rootless; }
docker_data_root()  { docker info -f '{{.DockerRootDir}}' 2>/dev/null; }

_under_home() { case "$1" in "$HOME"/*|"$HOME") return 0;; *) return 1;; esac; }

_rootless_sock() { echo "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/docker.sock"; }

# _rootless_env : point this shell's docker CLI at OUR daemon.
_rootless_env() {
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  export DOCKER_HOST="unix://$(_rootless_sock)"
}

rootless_running() { ( _rootless_env; docker_running && docker_is_rootless ); }

# --- pieces of the rootless setup -------------------------------------------

# _write_daemon_json <data-root> : keep the images off your home.
_write_daemon_json() {
  local droot="$1" cfg="$HOME/.config/docker/daemon.json"
  mkdir -p "$(dirname "$cfg")"
  cat > "$cfg" <<EOF
{
  "data-root": "$droot"
}
EOF
}

# _pick_rootless_net : choose the network helper, explicitly, so every machine
# behaves the same instead of "whatever happens to be installed".
_pick_rootless_net() {
  if [ -n "${VS_ROOTLESS_NET:-}" ]; then echo "$VS_ROOTLESS_NET"; return; fi
  if have slirp4netns && slirp4netns --help 2>/dev/null | grep -qw -- --netns-type; then
    echo slirp4netns                       # fastest of the three, prefer it
  elif have pasta; then
    echo pasta
  else
    echo gvisor-tap-vsock                  # built into rootlesskit, nothing to install
  fi
}

# _write_net_dropin <net> : record the choice where systemd will honour it.
_write_net_dropin() {
  local net="$1" d="$HOME/.config/systemd/user/docker.service.d"
  systemctl --user cat docker >/dev/null 2>&1 || return 0
  mkdir -p "$d"
  cat > "$d/10-devbox.conf" <<EOF
[Service]
Environment="DOCKERD_ROOTLESS_ROOTLESSKIT_NET=$net"
EOF
  systemctl --user daemon-reload >/dev/null 2>&1
  printf '%s\n' "$net" > "$VS_STATE_DIR/rootless-net"
}

_drop_net_dropin() {
  rm -f "$HOME/.config/systemd/user/docker.service.d/10-devbox.conf"
  systemctl --user daemon-reload >/dev/null 2>&1
  rm -f "$VS_STATE_DIR/rootless-net"
}

# _wait_rootless [tries] : true once our daemon answers.
_wait_rootless() {
  local i tries="${1:-40}"
  _rootless_env
  for i in $(seq 1 "$tries"); do rootless_running && return 0; sleep 0.5; done
  return 1
}

# _start_rootless : start (or restart) our daemon and wait for it. If it will
# not come up with our chosen network driver, drop that choice and try once more
# with docker's own default rather than leaving the developer with no docker.
_start_rootless() {
  _rootless_env
  if systemctl --user cat docker >/dev/null 2>&1; then
    systemctl --user restart docker >/dev/null 2>&1
  else
    pkill -f dockerd-rootless.sh >/dev/null 2>&1
    have dockerd-rootless.sh && nohup dockerd-rootless.sh >"$VS_STATE_DIR/dockerd.log" 2>&1 &
  fi
  _wait_rootless && return 0

  if [ -f "$HOME/.config/systemd/user/docker.service.d/10-devbox.conf" ]; then
    warn "rootless docker did not start with net=$(cat "$VS_STATE_DIR/rootless-net" 2>/dev/null) — retrying with the default"
    _drop_net_dropin
    systemctl --user restart docker >/dev/null 2>&1
    _wait_rootless && return 0
  fi
  return 1
}

# _install_rootless <data-root> : first-time setup. No root needed. The one
# thing it cannot do without root is /etc/subuid + /etc/subgid, which the
# distribution normally writes when the account is created; `check` says so.
_install_rootless() {
  local droot="$1"
  have dockerd-rootless-setuptool.sh || {
    warn "dockerd-rootless-setuptool.sh not found (docker >= 20.10 ships it)"; return 1; }

  _rootless_env
  if ! dockerd-rootless-setuptool.sh check --force >>"$VS_STATE_DIR/rootless-setup.log" 2>&1; then
    warn "this machine cannot run rootless docker yet — see rootless-setup.log"
    warn "usually means /etc/subuid + /etc/subgid have no line for $(id -un) (one-time root fix)"
    return 1
  fi

  _write_daemon_json "$droot"          # before first start, so no data lands in $HOME
  info "setting up your own rootless docker (no root needed) ..."
  dockerd-rootless-setuptool.sh install --force >>"$VS_STATE_DIR/rootless-setup.log" 2>&1 \
    || warn "rootless setup reported issues (see rootless-setup.log)"
  _write_net_dropin "$(_pick_rootless_net)"
  systemctl --user enable docker >/dev/null 2>&1
  _start_rootless
}

# --- how the rest of the world finds our docker ------------------------------

# link_docker_sock <socket> : publish it at one stable path. Dev containers
# mount THIS path, so devcontainer.json never mentions a machine-specific one.
link_docker_sock() {
  local sock="$1"
  mkdir -p "$(dirname "$VS_SOCK_LINK")"
  ln -sfn "$sock" "$VS_SOCK_LINK"
}

# write_env_d <docker-host> : make DOCKER_HOST reach programs started by the
# desktop (a VSCode launched from the applications menu), not only shells.
# Takes effect at the next login; shells get it immediately from login.sh.
write_env_d() {
  local dh="$1" f="$HOME/.config/environment.d/10-devbox.conf"
  mkdir -p "$(dirname "$f")"
  {
    echo "# written by devbox — your own docker daemon"
    [ -n "$dh" ] && echo "DOCKER_HOST=$dh"
    echo "DEVBOX_DOCKER_SOCK=$VS_SOCK_LINK"
  } > "$f"
}

# _record_mode <mode> [docker-host] : so login.sh exports DOCKER_HOST only when
# we really are on our own daemon.
_record_mode() {
  mkdir -p "$VS_STATE_DIR"
  printf '%s\n' "$1" > "$VS_STATE_DIR/docker-mode"
  if [ -n "${2:-}" ]; then printf '%s\n' "$2" > "$VS_STATE_DIR/docker-host"
  else rm -f "$VS_STATE_DIR/docker-host"; fi
}

# ensure_host_cli_plugins : one pinned compose + buildx for YOUR docker command,
# matching the versions baked into the dev-container images. Kept in the home
# cache (~120M, persists) so a machine switch costs no download. User plugins
# win over the machine's, and deleting the files undoes it.
ensure_host_cli_plugins() {
  [ "${VS_HOST_CLI_PLUGINS:-1}" = 1 ] || return 0
  local dir="$HOME/.docker/cli-plugins" cache="$VS_CACHE_DIR/cli-plugins"
  local a_dk a_go; a_dk="$(arch_tag docker)"; a_go="$(arch_tag go)"
  mkdir -p "$dir" "$cache"

  local want="$VS_COMPOSE_VERSION" f="$cache/docker-compose-$VS_COMPOSE_VERSION"
  if [ ! -x "$f" ]; then
    info "fetching docker compose $want (once) ..."
    fetch "https://github.com/docker/compose/releases/download/$want/docker-compose-linux-$a_dk" "$f.part" \
      && mv "$f.part" "$f" && chmod +x "$f" || { rm -f "$f.part"; warn "could not fetch compose $want"; }
  fi
  [ -x "$f" ] && ln -sfn "$f" "$dir/docker-compose"

  want="$VS_BUILDX_VERSION"; f="$cache/docker-buildx-$VS_BUILDX_VERSION"
  if [ ! -x "$f" ]; then
    info "fetching docker buildx $want (once) ..."
    fetch "https://github.com/docker/buildx/releases/download/$want/buildx-$want.linux-$a_go" "$f.part" \
      && mv "$f.part" "$f" && chmod +x "$f" || { rm -f "$f.part"; warn "could not fetch buildx $want"; }
  fi
  [ -x "$f" ] && ln -sfn "$f" "$dir/docker-buildx"
}

# --- the entry point ---------------------------------------------------------

# ensure_docker : leave this machine with a usable docker whose data is off your
# home. Returns 0 if docker works, even if it had to fall back to the shared one.
ensure_docker() {
  have docker || { warn "docker command not found"; return 1; }

  local droot; droot="$(store_path "$VS_DOCKER_DIR_NAME")" || {
    error "no usable store (goinfre/tmp)"; return 1; }
  printf '%s\n' "$droot" > "$VS_STATE_DIR/droot"

  # --- the standard path: our own daemon -----------------------------------
  if [ "$VS_DOCKER_MODE" != system ]; then
    if rootless_running; then
      _rootless_env
      if [ "$(docker_data_root)" != "$droot" ]; then
        info "moving your docker data -> $droot"
        _write_daemon_json "$droot"
        _start_rootless || warn "restart after the move failed"
      fi
    else
      _install_rootless "$droot" >/dev/null || true
    fi

    if rootless_running; then
      _rootless_env
      _record_mode rootless "$DOCKER_HOST"
      link_docker_sock "$(_rootless_sock)"
      write_env_d "$DOCKER_HOST"
      # Also make it the default for anything started WITHOUT our environment -
      # a program launched from the desktop menu, for instance. Otherwise that
      # program would quietly use the machine's root daemon instead of yours.
      if docker context inspect rootless >/dev/null 2>&1; then
        docker context use rootless >/dev/null 2>&1 || true
      fi
      ensure_host_cli_plugins
      ok "your own docker is ready — data-root: $(docker_data_root), socket: $VS_SOCK_LINK"
      return 0
    fi

    if [ "$VS_DOCKER_MODE" = rootless ]; then
      error "rootless docker could not be set up and VS_DOCKER_MODE=rootless — refusing to fall back"
      return 1
    fi
    warn "could not set up your own docker — falling back to the machine's shared one"
  fi

  # --- fallback: the machine's shared daemon -------------------------------
  unset DOCKER_HOST
  if ! docker_running; then
    error "no docker available (neither yours nor the machine's)"
    _record_mode none; return 1
  fi
  local cur; cur="$(docker_data_root)"
  _record_mode system
  link_docker_sock /var/run/docker.sock
  write_env_d ""
  ensure_host_cli_plugins
  _under_home "$cur" && warn "shared docker stores data under \$HOME ($cur) — it will eat your quota"
  warn "using the machine's shared docker: files a container writes into your project will be owned by root"
  warn "fix a folder afterwards with: devbox fix-perms [dir]"
  ok "docker ready (shared) — data-root: $cur"
  return 0
}
