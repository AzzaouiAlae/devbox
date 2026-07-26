# shellcheck shell=bash
# lib/ui.sh — the control panel (Avalonia), built once and kept in your home.
#
# It does not live on the store. 35M is not "big" by this repo's standard - the
# VSCode tarball in the same folder is ten times that - and keeping it in your
# home buys the thing the store can never give: after a machine switch it is
# simply already there. No unpack, no rebuild, no SDK, no docker.
#
# Two ways to build it:
#
#   local  — the machine's own .NET SDK. Fast, good for editing ui/.
#   docker — a container carries the SDK, so a machine that has none (every
#            school machine) can still produce the app. It builds NativeAOT on
#            AlmaLinux 9 on purpose: a .NET binary is linked against the glibc it
#            was built on and will not start on an older one, so we build on the
#            oldest glibc of the machines this runs on and it works on all of them.

ui_src()       { echo "$VS_SETUP_HOME/ui"; }
ui_dir()       { echo "$VS_UI_HOME"; }
ui_bin()       { echo "$VS_UI_HOME/app/devbox-ui"; }
ui_installed() { [ -x "$(ui_bin)" ]; }

# _ui_migrate : the app used to sit in ~/.cache/devbox/devbox-ui, and before that
# on the store. ~/.cache was a mistake: a cache is by definition disposable, and
# a session that clears it costs you a full rebuild at every login. Move what is
# already built rather than compiling it again.
_ui_migrate() {
  local old="$VS_CACHE_DIR/devbox-ui"
  [ -d "$old/app" ] || return 0
  [ "$old" = "$VS_UI_HOME" ] && return 0
  ui_installed && { rm -rf "$old"; return 0; }
  mkdir -p "$(dirname "$VS_UI_HOME")"
  if mv "$old" "$VS_UI_HOME" 2>/dev/null || { cp -a "$old" "$VS_UI_HOME" && rm -rf "$old"; }; then
    info "control panel moved to $VS_UI_HOME (out of ~/.cache, which machines are free to wipe)"
  fi
}

# ui_src_stamp : cheap fingerprint of the source, so a rebuilt app replaces a
# stale one and an unchanged one is never rebuilt.
#
# Two details, both learned the hard way, both making the same point: this must
# hash the SOURCE and nothing else, identically wherever it runs from.
#   * bin/ and obj/ are pruned. A local build drops generated .cs files in obj/,
#     which your checkout has and the copy in ~/.config does not.
#   * the list is sorted. `find` returns filesystem order, which differs between
#     those two copies.
# Get either wrong and the app rebuilds itself every time you alternate between
# running it from the checkout and from your home.
ui_src_stamp() {
  find "$(ui_src)" \( -name bin -o -name obj \) -prune -o \
       -type f \( -name '*.cs' -o -name '*.axaml' -o -name '*.csproj' \
                  -o -name 'Dockerfile.build' \) -print0 2>/dev/null \
    | sort -z | xargs -0 cat 2>/dev/null | cksum | cut -d' ' -f1
}

# _ui_builder : which of the two we are going to use, given what is installed.
#
# `auto` picks whoever can produce the AOT build, not whoever is fastest. That
# ordering is deliberate: this is the path that runs by itself (a fresh install,
# a changed ui/), and the artifact it produces is the one that gets cached in
# your home and carried to every other machine. A local SDK without clang cannot
# do AOT, so a container beats it even though it is slower.
#   Want the quick one while editing ui/?   VS_UI_BUILD=local make ui
_ui_builder() {
  case "${VS_UI_BUILD:-auto}" in
    local)  echo local;;
    docker) echo docker;;
    *)      if have dotnet && have clang; then echo local     # SDK that can AOT
            elif have docker;             then echo docker    # AOT in a container
            elif have dotnet;             then echo local     # single-file, last resort
            else echo none; fi;;
  esac
}

# _ui_build_local <outdir> : publish with the machine's SDK.
# NativeAOT needs a C toolchain (clang + zlib headers). Without one we fall back
# to a self-contained single file - same app, just bigger and slower to start,
# because it unpacks itself into /tmp on the first run.
_ui_build_local() {
  local out="$1" mode=(-p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true
                       -p:IncludeNativeLibrariesForSelfExtract=true)
  if have clang; then
    mode=(-p:PublishAot=true)
    info "building the control panel with the machine's SDK (NativeAOT) ..."
  else
    info "building the control panel with the machine's SDK (no clang: single-file, not AOT) ..."
  fi
  dotnet publish "$(ui_src)/Devbox.Ui.csproj" \
    -c Release -r "$VS_UI_RID" --self-contained true \
    "${mode[@]}" -p:DebugType=none -p:SatelliteResourceLanguages=en \
    -o "$out" >>"$VS_STATE_DIR/ui-build.log" 2>&1
}

# _ui_build_docker <outdir> : build in a container, copy the result out.
# Nothing is left running and nothing is mounted: the source goes in as build
# context, the finished folder comes out with docker cp.
_ui_build_docker() {
  local out="$1" img="$VS_UI_BUILDER_IMAGE" cid rc free
  have docker || { error "no docker to build the control panel in"; return 1; }
  docker version >/dev/null 2>&1 || { error "docker is installed but not reachable — run: setup-doctor"; return 1; }

  free="$(avail_gb "$(store_dir)")"
  if [ "$free" -lt "$VS_UI_BUILD_MIN_GB" ]; then
    warn "only ${free}G free on the store; the builder image wants ~${VS_UI_BUILD_MIN_GB}G"
    warn "if it fails: docker builder prune, or free space, then try again"
  fi

  info "building the control panel inside docker (the first one downloads a .NET SDK) ..."
  if ! docker build -f "$(ui_src)/Dockerfile.build" -t "$img" "$(ui_src)" \
        >>"$VS_STATE_DIR/ui-build.log" 2>&1; then
    error "the container build failed — see $VS_STATE_DIR/ui-build.log"
    return 1
  fi

  cid="$(docker create "$img" true 2>/dev/null)" || { error "could not create the builder container"; return 1; }
  docker cp "$cid:/out/." "$out/" >>"$VS_STATE_DIR/ui-build.log" 2>&1; rc=$?
  docker rm -f "$cid" >/dev/null 2>&1
  [ "$rc" -eq 0 ] || error "could not copy the built app out of the container"

  # And throw the builder away. It carries a whole .NET SDK - 5.7G on the store -
  # to produce a 22M binary you now have in your home. Keeping it would speed up
  # the next build, but the next build is rare and the space is not: on a school
  # goinfre this single image is the difference between working and not.
  # Set VS_UI_KEEP_BUILDER=1 while iterating on ui/ to keep it.
  if [ "${VS_UI_KEEP_BUILDER:-0}" != 1 ]; then
    docker rmi -f "$img" >/dev/null 2>&1 && info "removed the builder image (5G+ of SDK you do not need to keep)"
    docker builder prune -f >/dev/null 2>&1
  fi
  return "$rc"
}

# build_ui : produce the app, whichever way this machine can.
build_ui() {
  [ -f "$(ui_src)/Devbox.Ui.csproj" ] || { error "control panel source missing at $(ui_src)"; return 1; }
  local dir out; dir="$(ui_dir)"; out="$dir/.publish"
  mkdir -p "$dir"
  rm -rf "$out"; mkdir -p "$out"

  case "$(_ui_builder)" in
    local)  _ui_build_local "$out" || { rm -rf "$out"; error "build failed — see $VS_STATE_DIR/ui-build.log"; return 1; };;
    docker) _ui_build_docker "$out" || { rm -rf "$out"; return 1; };;
    *)      rm -rf "$out"
            error "this machine has neither a .NET SDK nor docker — cannot build the control panel"
            return 1;;
  esac

  [ -x "$out/devbox-ui" ] || { error "the build produced no devbox-ui binary"; rm -rf "$out"; return 1; }

  # Swap it in whole: a half-copied app is an app that does not start.
  rm -rf "$dir/app.old"
  [ -d "$dir/app" ] && mv "$dir/app" "$dir/app.old"
  mv "$out" "$dir/app"
  rm -rf "$dir/app.old"
  # Where it used to live, before it moved into your home.
  rm -f "$VS_CACHE_DIR/devbox-ui-linux-x64.gz" "$VS_CACHE_DIR/devbox-ui-linux-x64.tar.gz" \
        "$VS_CACHE_DIR/devbox-ui-linux-x64.tar.gz.stamp"
  [ -n "${VS_STORE:-}" ] && rm -rf "$VS_STORE/devbox-ui"

  # The stamp records WHICH source this was built from, so a later run can tell
  # "you edited ui/" apart from "this was built somewhere else".
  ui_src_stamp > "$dir/.stamp"
  ok "control panel built: $(ui_bin) ($(du -sh "$dir/app" 2>/dev/null | cut -f1))"
}

# ensure_ui [--build|--refresh] : make the app runnable.
#
#   (nothing)  it exists -> run it. Missing -> build it.
#   --refresh  also rebuild when ui/ has changed since (what install.sh wants,
#              because it has just copied a possibly newer ui/ into place).
#   --build    rebuild now, no questions.
#
# The default deliberately does NOT rebuild on a changed source. This is what the
# `devbox-ui` shim calls, and the shim runs with VS_SETUP_HOME pointing at your
# HOME copy - so "the source changed" is also true right after `make ui` built
# the app from your checkout. Rebuilding there would silently throw away the
# build you just made and put the older installed source back.
ensure_ui() {
  _ui_migrate
  case "${1:-}" in
    --build)
      build_ui && return 0
      ui_installed && { warn "keeping the control panel that is already installed"; return 0; }
      return 1;;
    --refresh)
      if ui_installed && [ "$(cat "$(ui_dir)/.stamp" 2>/dev/null)" = "$(ui_src_stamp)" ]; then
        return 0
      fi
      ui_installed && info "ui/ changed since the app was built — rebuilding"
      build_ui && return 0
      ui_installed && { warn "rebuild failed; keeping the app that is already there"; return 0; }
      return 1;;
  esac

  ui_installed && return 0
  build_ui
}

# ensure_ui_shim : `devbox-ui` in your home, so the app is on PATH and on the
# GNOME app list. It resolves the binary at run time rather than hard-coding it,
# so it keeps working after a rebuild moves the app.
ensure_ui_shim() {
  mkdir -p "$VS_BIN_DIR"
  cat > "$VS_BIN_DIR/devbox-ui" <<'EOF'
#!/usr/bin/env bash
# written by devbox — finds the control panel in your home, building it once if
# this account has never had it.
: "${VS_SETUP_HOME:=$HOME/.config/vscode-setup}"
[ -f "$VS_SETUP_HOME/lib/ui.sh" ] || {
  echo "devbox: $VS_SETUP_HOME is older than this app — run 'make install' in your devbox checkout" >&2
  exit 1
}
. "$VS_SETUP_HOME/config.sh"
. "$VS_SETUP_HOME/lib/common.sh"
. "$VS_SETUP_HOME/lib/vscode.sh"
. "$VS_SETUP_HOME/lib/ui.sh"
ensure_ui || { echo "devbox: the control panel is not available (see: setup-doctor)" >&2; exit 1; }
exec "$(ui_bin)" "$@"
EOF
  chmod +x "$VS_BIN_DIR/devbox-ui"

  # Three ways to open it, because a window nobody can find is a window nobody
  # uses: the app grid, a hotkey, and `devbox ui` in a terminal.
  local apps="$HOME/.local/share/applications"
  local icons="$HOME/.local/share/icons/hicolor/scalable/apps"
  mkdir -p "$apps" "$icons"
  [ -f "$(ui_src)/devbox-ui.svg" ] && cp -f "$(ui_src)/devbox-ui.svg" "$icons/devbox-ui.svg"

  cat > "$apps/devbox-ui.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=devbox
Comment=Dev container control panel
Exec=$VS_BIN_DIR/devbox-ui %f
Icon=devbox-ui
Terminal=false
Categories=Development;
Keywords=devcontainer;docker;vscode;devbox;
StartupWMClass=devbox-ui
EOF
  chmod +x "$apps/devbox-ui.desktop"
  have update-desktop-database && update-desktop-database "$apps" >/dev/null 2>&1
  have gtk-update-icon-cache && gtk-update-icon-cache -qtf "$HOME/.local/share/icons/hicolor" 2>/dev/null

  # Slot 1: slot 0 is already VSCode's Ctrl+Alt+C. Set VS_UI_HOTKEY= to skip it.
  gnome_keybinding 1 "devbox control panel" "$VS_BIN_DIR/devbox-ui" "${VS_UI_HOTKEY:-}"
  return 0
}
