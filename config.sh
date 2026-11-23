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

# --- your own store location -------------------------------------------------
# Two different questions, two different files, and conflating them is a bug:
#
#   VS_STORE_RECORD  (state)  "what we auto-picked on THIS machine"
#                             disposable, re-answered whenever it stops working
#   VS_STORE_PREF    (setup)  "where I told you to put it"
#                             sticky, follows you, survives a reinstall
#
# The preference exists for storage that is not one of the two known spots: an
# external disk, a second internal drive, a big /data partition. Point it there
# once and every machine uses it.
#
# It is a preference and not an override, because the disk it names may simply
# not be plugged in today. When the path is not usable we say so and fall back
# to the normal goinfre/tmp pick - we do NOT forget it, so plugging the disk
# back in is all it takes to go back to using it.
: "${VS_STORE_PREF_FILE:=$VS_SETUP_HOME/store-path}"
if [ -z "${VS_STORE_PREF:-}" ] && [ -r "$VS_STORE_PREF_FILE" ]; then
  VS_STORE_PREF="$(sed -n '1p' "$VS_STORE_PREF_FILE" 2>/dev/null)"
fi
: "${VS_STORE_PREF:=}"

# --- your own tools, for the editor ------------------------------------------
# VSCode opened from the panel, the shortcut or the desktop never reads ~/.zshrc
# or ~/.bashrc: its `bin/code` launcher marks the start as "from a terminal", so
# the editor keeps the bare desktop environment instead of asking your shell.
# Extensions then run `dotnet`, `node`... through /bin/sh and report them missing
# when they live outside /usr (an external disk, ~/.local/...).
#
# The `code` shim sources this file right before starting the editor: put the
# exports your shell rc adds for those tools (PATH, DOTNET_ROOT...). Yours, like
# store-path: a reinstall keeps it.
: "${VS_USER_ENV_FILE:=$VS_SETUP_HOME/user-env.sh}"

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
# The two lists below are installed the same way, on every machine. Each id is
# installed ONCE (a list in your home remembers which), never re-forced:
# uninstall one and it stays gone. They join your saved list, so a wiped store
# puts them back like the rest. An id you ADD here is picked up at the next
# login; `devbox ext extras` installs it right now.
#
# The editor you actually want.
: "${VS_EXTRA_EXTENSIONS:=\
PKief.material-icon-theme \
monokai.theme-monokai-pro-vscode \
Photopea.photopea \
anthropic.claude-code \
ritwickdey.LiveServer}"
# The languages and tools your projects use, for working on the MACHINE (the
# tools themselves come from user-env.sh). A dev container does not see these:
# its own devcontainer.json lists what it needs.
#   Angular + TS : language service, ESLint, Prettier
#   Tailwind     : class IntelliSense, in Angular templates and plain HTML/CSS
#   C# / .NET    : C# Dev Kit + the C# extension and the .NET install tool it
#                  runs on; Avalonia for .axaml (the control panel in ui/)
#   C/C++        : the Makefile projects
#   the rest     : Dockerfile/compose, YAML (CI), .editorconfig (`ng new`
#                  writes one), ShellCheck (this repo), REST Client for the
#                  .http file `dotnet new webapi` writes, Live Preview for HTML
: "${VS_STACK_EXTENSIONS:=\
angular.ng-template \
dbaeumer.vscode-eslint \
esbenp.prettier-vscode \
bradlc.vscode-tailwindcss \
ms-dotnettools.csdevkit \
ms-dotnettools.csharp \
ms-dotnettools.vscode-dotnet-runtime \
avaloniateam.vscode-avalonia \
ms-vscode.cpptools \
ms-azuretools.vscode-containers \
redhat.vscode-yaml \
editorconfig.editorconfig \
timonwong.shellcheck \
humao.rest-client \
ms-vscode.live-server}"
# Editor defaults, written into your VSCode settings.json ONCE per machine
# home (never again after that, so changing them in VSCode sticks). A setting
# you already have is never overwritten. Empty = leave that setting alone.
#   VS_ICON_THEME   : the file icon theme ("material-icon-theme" comes from
#                     PKief.material-icon-theme above)
#   VS_IMAGE_EDITOR : what opens .png/.jpg/.jpeg/.svg. Photopea registers itself
#                     as the default for those; this keeps VSCode's own image
#                     preview as the default instead. Photopea is still one
#                     right-click away: "Reopen Editor With..." -> Photopea.
: "${VS_ICON_THEME=material-icon-theme}"
: "${VS_IMAGE_EDITOR=imagePreview.previewEditor}"
# Cleaning up after VSCode (its caches live in your home and only ever grow).
# Runs by itself in the background at login, at most once per interval; also
# `devbox clean`. Never touches your settings, extensions or their saved data -
# see clean_vscode_caches in lib/vscode.sh for exactly what it deletes.
: "${VS_CLEAN_INTERVAL_HRS:=24}"    # 0 = never on its own, only `devbox clean`
: "${VS_CLEAN_KEEP_LOGS:=3}"        # VSCode log sessions to keep
: "${VS_CLEAN_HOME_MIN_MB:=500}"    # below this much free home, also drop the
                                    # saved VSCode download (it re-downloads)
# The same for your web browsers' caches - never your bookmarks, logins,
# history or settings (see lib/cleanup.sh). Only while the browser is closed.
# Folder names under ~/.config and ~/.cache; any Chromium-based browser works.
: "${VS_CLEAN_BROWSER:=1}"          # 0 = leave browsers alone
: "${VS_CLEAN_BROWSERS:=google-chrome google-chrome-beta chromium BraveSoftware/Brave-Browser microsoft-edge}"
# 1 = keep the VSCode download in your home, so a fresh machine costs no download.
# 0 = keep it on the store: smaller home, one download per machine switch.
: "${VS_CACHE_TARBALL:=1}"

# --- the control panel (Avalonia GUI) ----------------------------------------
# In ~/.local/share, NOT the store and NOT ~/.cache. Three separate reasons:
#   * not the store: goinfre/tmp is wiped per machine, and 35M is not "big" by
#     this repo's standard - the VSCode tarball is ten times it.
#   * not ~/.cache: a cache is by definition disposable, and machines act on that
#     definition. A school session that clears it makes you rebuild every login.
#   * ~/.local/share is where an installed program belongs, beside the .desktop
#     entry and the icon that already live there.
: "${VS_UI_HOME:=$HOME/.local/share/devbox/ui}"        # the app itself, ~35M
: "${VS_UI_RID:=linux-x64}"
# How to build it:
#   auto   : the machine's .NET SDK if it has one, else inside docker
#   local  : the machine's SDK only
#   docker : always in a container - the school-machine answer, and the only one
#            that pins the glibc the binary is linked against (see ui/Dockerfile.build)
: "${VS_UI_BUILD:=auto}"
: "${VS_UI_BUILDER_IMAGE:=devbox-ui-builder}"
: "${VS_UI_BUILD_MIN_GB:=4}"        # a container build needs about this much room
# GNOME shortcut that opens the panel. Empty = do not set one. VSCode already
# owns Ctrl+Alt+C, so this is the second slot.
: "${VS_UI_HOTKEY:=<Control><Alt>d}"

export VS_SETUP_HOME VS_STATE_DIR VS_CACHE_DIR VS_BIN_DIR VS_SOCK_LINK \
       VS_GOINFRE VS_TMP VS_STORE VS_HOME VS_STORE_PREF VS_STORE_PREF_FILE
