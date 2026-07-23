# shellcheck shell=bash
# config.sh — tunable settings for the vscode/docker school setup.
# Everything is overridable from the environment (: "${VAR:=default}") so you
# can tweak a single machine without editing files.

# --- where things live -------------------------------------------------------
# VSCode installer dir + extracted app root (matches your manual script layout).
# Persists in your 5G home / NFS across machines.
: "${VS_INSTALLER_DIR:=$HOME/vsCodeInstaller}"
: "${VS_HOME:=$VS_INSTALLER_DIR/VSCode-linux-x64}"   # bin/code lives at $VS_HOME/bin/code
# These scripts, once installed into home (persistent).
: "${VS_SETUP_HOME:=$HOME/.config/vscode-setup}"
# Small state: markers, logs, chosen-store record (persistent, tiny).
: "${VS_STATE_DIR:=$HOME/.local/state/vscode-setup}"

# --- heavy / ephemeral storage (wiped when you switch machines) --------------
# Candidate locations for docker data, in priority order. First writable one
# with enough free space wins. goinfre (~30G) preferred, /tmp (~256G) fallback.
: "${VS_GOINFRE:=/goinfre/$USER}"
: "${VS_TMP:=/tmp/$USER}"
# Minimum free GB a location must have to be chosen for docker data.
: "${VS_DOCKER_MIN_GB:=6}"

# --- behaviour ---------------------------------------------------------------
# Skip the (slightly heavier) health re-check if we passed within this window.
# Keeps opening new terminals instant.
: "${VS_HEALTH_TTL_MIN:=60}"
# Only check for a newer VSCode at most once per this many hours.
: "${VS_UPDATE_INTERVAL_HRS:=24}"
# Latest stable VSCode for linux x64 (always newest — no version pinning).
: "${VS_CODE_URL:=https://code.visualstudio.com/sha/download?build=stable&os=linux-x64}"
# The one host extension we need so "Reopen in Container" works.
: "${VS_HOST_EXTENSIONS:=ms-vscode-remote.remote-containers}"

export VS_HOME VS_INSTALLER_DIR VS_SETUP_HOME VS_STATE_DIR VS_GOINFRE VS_TMP
