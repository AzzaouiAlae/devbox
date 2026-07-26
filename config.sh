# shellcheck shell=bash
# config.sh — every tunable in one place. All of them are overridable from the
# environment (: "${VAR:=default}"), so you can change one machine without
# editing any file: export the variable in ~/.bashrc / ~/.zshrc BEFORE the hook.

# --- tier 1: small, must survive a machine switch -> your home ---------------
: "${VS_SETUP_HOME:=$HOME/.config/vscode-setup}"        # these scripts
: "${VS_STATE_DIR:=$HOME/.local/state/vscode-setup}"    # markers, logs, choices
: "${VS_CACHE_DIR:=$HOME/.cache/devbox}"                # the VSCode download (341M)
: "${VS_BIN_DIR:=$HOME/.local/bin}"                     # the `code` shim lives here
: "${VS_EXT_MANIFEST:=$VS_SETUP_HOME/extensions.txt}"   # your extension list
: "${VS_SOCK_LINK:=$HOME/.devbox/docker.sock}"          # stable path to YOUR docker

# --- tier 2: big, disposable, rebuilt per machine -> goinfre, else /tmp -------
# Same layout on every machine: school, VM, your own laptop.
: "${VS_GOINFRE:=/goinfre/$USER}"
: "${VS_TMP:=/tmp/$USER}"
: "${VS_DOCKER_MIN_GB:=6}"          # a store needs this much free to be chosen
# Machines that are not school machines have no /goinfre. Create it (needs sudo
# once) so every machine looks the same. No sudo -> we fall back to /tmp.
: "${VS_GOINFRE_CREATE:=1}"
# Where the chosen store is remembered, so every later shell agrees.
: "${VS_STORE_RECORD:=$VS_STATE_DIR/store}"
if [ -z "${VS_STORE:-}" ] && [ -r "$VS_STORE_RECORD" ]; then
  VS_STORE="$(cat "$VS_STORE_RECORD" 2>/dev/null)"
fi

# --- what lives on the store -------------------------------------------------
# VSCode itself now lives beside its extensions, off your home entirely.
: "${VS_HOME:=${VS_STORE:-$VS_TMP}/vscode/VSCode-linux-x64}"   # bin/code is here
: "${VS_EXT_DIR_NAME:=vscode-extensions}"      # $store/<name>  <- ~/.vscode/extensions
: "${VS_CODE_CACHE_NAME:=vscode-cache}"        # $store/<name>  <- ~/.config/Code caches
: "${VS_DOCKER_DIR_NAME:=docker/data}"         # $store/<name>  <- docker data-root
# The pre-rewrite location, moved onto the store on the first run (then deleted).
: "${VS_LEGACY_INSTALLER_DIR:=$HOME/vsCodeInstaller}"

# --- docker ------------------------------------------------------------------
# rootless is the standard on every machine: the daemon runs as YOU, so a file a
# container writes into your project stays yours, and handing its socket to a dev
# container hands over your own daemon - not root's.
#   auto     : rootless when the machine can (it almost always can), else system
#   rootless : rootless only; fail loudly rather than fall back
#   system   : use the machine's shared daemon (files will be root-owned)
: "${VS_DOCKER_MODE:=auto}"
# One pinned docker client set, used in two places: your own CLI and every dev
# container image. Same versions inside and outside - that is the whole point.
: "${VS_DOCKER_CLI_VERSION:=29.6.2}"
: "${VS_COMPOSE_VERSION:=v5.3.1}"
: "${VS_BUILDX_VERSION:=v0.35.0}"
: "${VS_HOST_CLI_PLUGINS:=1}"       # also install pinned compose/buildx for your CLI
# Rootless network driver. Empty = pick the best installed one and record it.
: "${VS_ROOTLESS_NET:=}"

# --- behaviour ---------------------------------------------------------------
: "${VS_HEALTH_TTL_MIN:=60}"          # skip the heavy check if we passed recently
: "${VS_UPDATE_INTERVAL_HRS:=24}"     # check for a newer VSCode at most this often
: "${VS_CODE_URL:=https://code.visualstudio.com/sha/download?build=stable&os=linux-x64}"
: "${VS_HOST_EXTENSIONS:=ms-vscode-remote.remote-containers}"  # needed for containers
# The editor you actually want, on every machine. Installed ONCE (a marker in
# your home remembers it), never re-forced: uninstall one and it stays gone.
# They join your saved list, so a wiped store puts them back like the rest.
# Add or remove ids here, then: devbox ext extras
: "${VS_EXTRA_EXTENSIONS:=\
PKief.material-icon-theme \
monokai.theme-monokai-pro-vscode \
hediet.vscode-drawio \
pomdtr.excalidraw-editor \
Photopea.photopea \
anthropic.claude-code \
yzhang.markdown-all-in-one}"
# 1 = keep the VSCode download in your home, so a fresh machine costs no download.
# 0 = keep it on the store: smaller home, one download per machine switch.
: "${VS_CACHE_TARBALL:=1}"

export VS_SETUP_HOME VS_STATE_DIR VS_CACHE_DIR VS_BIN_DIR VS_SOCK_LINK \
       VS_GOINFRE VS_TMP VS_STORE VS_HOME
