# devbox — the same dev environment on every machine

One setup that gives every developer the **same tools everywhere**: a school
machine, a virtual machine, or their own laptop. Install once; from then on it
repairs itself on every login, on any machine, and the only thing that changes
per machine is *where the big files sit*.

It gives you three things:

1. **VSCode + Dev Containers**, with the heavy parts kept out of your small home.
2. **Your own docker**, which runs as *you* — not as root.
3. **Docker that works from inside your dev container**, so you can `docker build`
   and `docker compose up` without leaving the editor.

---

## The problem this solves

On school machines storage fights against normal dev tools:

| Location | Size | Survives a machine switch? |
|---|---|---|
| Your home (`~`) | **~5 GB** | ✅ yes (on NFS, follows you) |
| `/goinfre/$USER` | ~30 GB | ❌ no (local to that machine) |
| `/tmp/$USER` | large | ❌ no (local, wiped) |

Docker images, VSCode itself and its extensions easily reach **10–20 GB**. In your
home you hit the wall in a day. Only on goinfre, everything vanishes when you sit
at another machine.

**The trick:** keep the *small* things that must survive in your home, put every
*big, rebuildable* thing on goinfre/tmp, and rebuild the big things automatically
when you land on a fresh machine.

---

## What goes where

| Thing | Where | Why there |
|---|---|---|
| The VSCode download (`.tar.gz`, 341 MB) | `~/.cache/devbox/` | Keeping it means a fresh machine costs **no download**. Set `VS_CACHE_TARBALL=0` to keep it on the store instead: smaller home, one download per machine |
| Your settings, keybindings, snippets | `~/.config/Code/User/` | Tiny, must never be lost |
| Your **extension list** | `~/.config/vscode-setup/extensions.txt` | So a wiped machine can put your extensions back |
| The pinned compose + buildx (94 MB) | `~/.cache/devbox/cli-plugins/` | Same versions inside and outside the container, no re-download |
| The `code` command | `~/.local/bin/code` (a small shim) | So `code` never becomes "command not found" |
| Your project code | your home | Small, must never be lost |
| **VSCode itself** (~1.1 GB) | `$store/vscode/` | Big and re-extractable |
| **Extensions** (~1.5 GB) | `$store/vscode-extensions/` | Big and re-downloadable |
| The control panel **source** | `~/.config/vscode-setup/ui/` | A few hundred KB, must survive |
| The control panel (35 MB) | `~/.cache/devbox/devbox-ui/` | Rebuildable, but small enough not to bother: keeping it means a machine switch needs no SDK, no docker and no unpacking |
| VSCode's caches | `$store/vscode-cache/` | Pure junk that grows forever |
| **Docker data** (images, containers, volumes) | `$store/docker/data/` | Huge and rebuildable — **never** your home |

`$store` is `/goinfre/$USER`, or `/tmp/$USER` when there is no goinfre. Check
which one you got with `devbox where`.

---

## Install (once per account)

```bash
cd devbox
make install
```

That does five things:

1. Copies itself into `~/.config/vscode-setup/` (your persistent home).
2. Adds a small hook to **both** `~/.bashrc` and `~/.zshrc` — school machines use
   zsh, a personal Fedora/Rocky/Ubuntu box uses bash, and hooking only one is how
   a machine silently never repairs itself.
3. Sets up **your own rootless docker**.
4. Provisions the machine you are on right now.
5. Builds the **control panel** (see below) — with this machine's .NET SDK if it
   has one, in a container if it does not, and straight out of your home cache if
   it has been built before.

Open a new terminal (or `source ~/.bashrc`) to pick up the PATH change.

### The only two steps that need a password

Both are one-time, both are optional, and both are skipped automatically when
sudo is not available:

| Step | Why | Without it |
|---|---|---|
| create `/goinfre/$USER` | so a VM or laptop has the same layout as school | falls back to `/tmp/$USER` |
| `loginctl enable-linger` | so your containers survive logging out | containers stop when you log out |

Run them later at any time with `devbox goinfre`.

---

## Daily use

```bash
cd ~/projects/my-app
devbox init angular      # angular | dotnet | cpp | base
devbox open              # then: Dev Containers: Reopen in Container
```

`devbox init` writes a `.devcontainer/` (a `devcontainer.json` **and** a
`Dockerfile`) into your project. From then on it is your project's file: commit it,
review it, edit it.

Language extensions install *inside* the container, on the store — not in your home.

Your **own** extensions are not in there, and do not need to be: themes, icon
themes and the drawing editors run on the machine side of the remote split, so the
copy devbox installed for you shows up inside every container by itself. Only an
extension that must run *where the code is* needs a line in `devcontainer.json` —
which is why `anthropic.claude-code` and `yzhang.markdown-all-in-one` are the two
the templates list.

### The control panel

A small always-on-top window for the same commands, for when you would rather not
type them:

```bash
devbox ui          # or: devbox-ui, or "devbox" in your app list
```

It is a **thin driver over the CLI** and owns no behaviour of its own. Every button
runs the same `devbox …` you would type, in the folder you picked, and the output
pane shows the command and everything it printed. There is nothing the window can
do that the terminal cannot, which is the point: one behaviour, one place to fix it.

| In the window | What it runs |
|---|---|
| **Choose…** | nothing — it just picks the folder every other button works in |
| the template list | `devbox templates`, so a new template folder appears by itself |
| **Create / Change setup** | `devbox init <template> [--network …] [--force]` |
| **Set** / **Clear** network | `devbox network <name>` / `devbox network --none` |
| the compose hint under it | fills in the network your `docker-compose.yml` declares |
| **Open in VSCode** / **Open in container** | `devbox open` / `devbox container` — the two you actually press |
| **Tools ▾** | everything else, one click away: `fix-perms`, `check-versions`, `doctor`, `where`, a full repair, `update`, `ext save`, `ext extras`, `up`, `down` |
| Tools → **Shell in it**, **Create /goinfre**, **Follow the setup log** | open a terminal — those three need a tty |

Changing the template is the one destructive button, so it behaves the way the CLI
does: picking the template you already have does nothing, picking a different one
replaces `.devcontainer/` and keeps your old copy as `.devcontainer.bak`, and the
shared network survives the swap. `force` replaces it even when nothing changed.

**Running it needs nothing** — no .NET runtime, no SDK. Building it needs one of
two things, and the second is the one that matters at school:

| Build | When | What you get |
|---|---|---|
| the machine's **.NET SDK** | `make ui` on a box that has one | fast to rebuild while editing `ui/` |
| **inside docker** | `make ui-docker`, or automatically when there is no SDK | NativeAOT: a 22 MB native binary that needs no runtime |

School machines have no SDK — but devbox already gave you **your own docker**, so
the SDK goes in a container and only the finished binary comes out:

```bash
make ui-docker           # or: devbox ui --docker
```

Two deliberate choices in [`ui/Dockerfile.build`](ui/Dockerfile.build):

- **NativeAOT**, so the result is a real native binary. It starts instantly and,
  unlike a compressed single-file build, never unpacks itself into `/tmp` on
  startup — which matters on a machine where `/tmp` is also the fallback store.
- **AlmaLinux 9 as the base, not the official `dotnet/sdk` image.** A .NET binary
  is linked against the glibc it was built on and will *not* start on an older
  one. The SDK images are Debian 12 (2.36) or Ubuntu 24.04 (2.39); the machines
  this runs on are EL9 (2.34). Building on the oldest glibc of the lot is what
  makes one artifact work on all of them — `objdump -T` on the result asks for
  nothing newer than `GLIBC_2.34`.

The build takes about three minutes the first time (it downloads an SDK into the
image) and seconds after that. The builder image stays on the store, where a
machine switch drops it anyway; reclaim it early with
`docker rmi devbox-ui-builder`.

Unlike VSCode or your extensions, the built app then stays in your **home**
(`~/.cache/devbox/devbox-ui/`). 35 MB is not "big" by this repo's standard — the
VSCode tarball in that same folder is ten times it — and keeping it buys the one
thing the store cannot: on the next machine it is simply already there. Nothing
to unpack, nothing to rebuild, no SDK and no docker needed to *run* it.

The app is rebuilt only when you ask (`make ui`, `make ui-docker`) or when
`make install` copies in a `ui/` that differs from what the current app was built
from. Launching it never rebuilds it — otherwise running the app from your home
copy would quietly undo a build you just made from your checkout.

Which one `auto` picks is decided by *what can produce the AOT build*, not by
what is fastest: a local SDK **with clang**, else docker, else a local single-file
build. That ordering matters because the automatic path — a fresh install, or a
`ui/` you edited — is what fills the cache your other machines will unpack. While
editing `ui/` and wanting the 40-second loop instead of the 3-minute one:

```bash
VS_UI_BUILD=local make ui
```

### Docker from inside the dev container

It just works. There is **no second docker engine** inside: the container gets the
docker *command*, and it talks to the engine already running on your machine
through a socket the template mounts. Nothing is nested, images are shared with
the machine, and nothing needs root.

Two rules follow from that, and they are the only two surprises:

1. **A path means the same thing inside and outside.** The templates mount your
   project at its real path for exactly this reason: the engine is outside, so
   `docker compose` reads paths as the *machine* sees them. Do not "tidy" that
   into `/workspaces/...` or compose will look for files that are not there.
2. **Ports you publish appear on the machine, not in the container.** After
   `docker compose up`, open the address in your normal browser. `forwardPorts`
   only matters for servers you run *in* the dev container (like `ng serve`).

### Reaching the project's other containers

A dev container can only reach other containers **by name** if it is on the same
docker network. Which network that is belongs to the project, not to devbox — one
repository calls it `topoease`, the next calls it something else — so it is an
option, and most projects need none at all:

```bash
devbox init dotnet --network topoease   # wire it while scaffolding
devbox network                          # what is it wired to? (prints "(none)" if nothing)
devbox network topoease                 # set or change it later
devbox network a,b                      # more than one
devbox network --none                   # unwire it
devbox up --network topoease            # same for the throwaway container
```

Two lines are written into your `devcontainer.json`, editable like any other:
`initializeCommand` creates the network on the machine if nobody has yet, and
`postStartCommand` joins it on every start. If the project's compose file declares
a fixed network name, `devbox init` notices and tells you the command to adopt it.

Rebuild (or restart) the container after changing it.

### The `devbox` commands

| Command | What it does |
|---|---|
| `devbox ui [--build\|--docker] [dir]` | The control panel (small, always on top) |
| `devbox init <type> [--network <name>] [--force]` | Scaffold `.devcontainer/`; changing type replaces it |
| `devbox templates` | The template names, one per line |
| `devbox network [<name>\|--none]` | Show, set, or remove the shared network of an existing project |
| `devbox open [dir]` | Open a folder in VSCode |
| `devbox container [dir]` | Open it already attached to its dev container |
| `devbox up [image]` | Quick throwaway container, home mounted, docker inside |
| `devbox shell` | Shell into that throwaway container |
| `devbox down` | Stop & remove it |
| `devbox where` | Store, docker mode, socket, pinned versions |
| `devbox ext save\|restore\|list\|extras` | Your extension list (`extras` installs the ones `config.sh` asks for) |
| `devbox fix-perms [dir]` | Take back files a container created |
| `devbox goinfre` | Create `/goinfre/$USER` (asks for sudo once) |
| `devbox check-versions [repo]` | Every place that pins Node must agree |
| `devbox doctor` | Full status report |

---

## Your own docker (rootless), and why it matters

Rootless means **the docker engine runs as you**. That is not a detail:

- **Files stay yours.** In a normal (root) docker, a container writing into your
  project leaves root-owned files — thousands of them under `node_modules`. With
  your own engine, "root" inside the container *is* you outside it, so files come
  out owned by you.
- **Sharing the socket is safe.** The dev container gets *your* engine, not root's.
- **The templates are correct.** That is why they say `"remoteUser": "root"` and
  `"updateRemoteUserUID": false`. Do not change those: with rootless docker,
  container-root is the mapping that lands your own user id on the files.

Set up with no root at all. The one thing it needs from the system is a line for
your account in `/etc/subuid` and `/etc/subgid`, which distributions normally write
when the account is created; `setup-doctor` tells you when it is missing.

Its data lives on the store, and the socket is always published at one stable
path — `~/.devbox/docker.sock` — which is what makes one `devcontainer.json` work
on every machine with no edits.

**If a machine cannot do rootless**, devbox falls back to the shared system docker
and says so loudly. Everything still works, but files a container writes into your
project will be root-owned; `devbox fix-perms` takes them back.

---

## Pinned versions (why they are pinned, and where)

Everybody gets the **same client versions**, inside the container and out:
docker CLI, `docker compose`, `docker buildx` — all pinned in `config.sh`, and
installed both for your shell and into each dev-container image.

Node is pinned to an **exact** version in the Angular template, because a Node
version normally lives in several files at once:

| Place | Why it is there |
|---|---|
| `.nvmrc` | so a developer switches with one command |
| `engines` in `package.json` | so npm complains when the version is wrong |
| the build stage of the app's `Dockerfile` | so the image builds on that version |
| `ARG NODE_VERSION` in `.devcontainer/Dockerfile` | so you *write* code on that version |

If those disagree, you develop on one Node and build on another, and nothing in the
source looks wrong. `devbox check-versions` prints all four and fails when they
differ — run it locally, and run it in CI.

`devbox init angular` reads your project's `.nvmrc` (if it has one) and pins the
dev container to that version automatically.

---

## Check & repair

`make` on its own lists everything. From anywhere: `setup-doctor <action>`.

| Command | What it does |
|---|---|
| `make doctor` | Full status: storage, VSCode, your docker, hooks |
| `make fix` | Force a full re-provision |
| `make where` | The short version |
| `make update` | Pull the latest VSCode and re-extract it |
| `make goinfre` | Create `/goinfre/$USER` (asks for sudo once) |
| `make ext-save` | Save your extension list right now |
| `make ui` | Build the control panel from this checkout |
| `make ui-docker` | Build it in a container (no .NET SDK needed) |
| `make ui-run` | Build it and open it on the current folder |
| `make logs` | Follow the setup log |
| `make reset` | Forget state; next login rebuilds |
| `make check` | Syntax-check scripts + validate templates (no install) |
| `make smoke` | Run the commands for real and check what they produce |
| `make uninstall` | Remove the hooks + scripts (keeps VSCode & docker data) |
| `make purge` | ⚠️ Also delete the store and the caches |

---

## How it stays fast

- **`login.sh`** runs on *every* shell and only does the cheap thing: PATH and
  `DOCKER_HOST`. Instant.
- **`ensure.sh`** does the real checking (VSCode, store, docker) and runs only when
  the machine looks unprovisioned or the last good check is older than an hour
  (`VS_HEALTH_TTL_MIN`, default 60).

So the first login on a fresh machine takes a moment; every terminal after that is
immediate.

---

## Two levels of checking

- **`make check`** reads the scripts (`bash -n`) and validates the templates. Fast,
  needs no install. It cannot catch a command that breaks only when it runs.
- **`make smoke`** runs the commands for real in a temporary folder and checks what
  they produce: every template scaffolds a valid pair of files, `init` picks up a
  Node version the project already pins, `check-versions` says yes when the versions
  agree and no when they do not. Run it after editing anything here.

## Good to know

- **A machine switch wipes the store. That is the design.** VSCode is re-extracted
  from the tarball already in your home (no download), your extensions reinstall
  from the saved list in the background, and docker re-pulls images. You wait once.
- **The extension list never shrinks by itself.** Right after a switch the store is
  empty and the reinstall is still running — saving *then* would throw away the
  list we need. Use `devbox ext save` after you really did remove extensions.
- **The extensions you asked for are installed once, not enforced.** `config.sh`
  (`VS_EXTRA_EXTENSIONS`) lists Material Icon Theme, Monokai Pro, Draw.io,
  Excalidraw, Photopea, Claude Code and Markdown All in One. devbox installs whichever are missing the
  first time, then remembers it did: uninstall one and it stays uninstalled. Edit
  that list and run `devbox ext extras` to pick up the change.
- **The moves wait for you to close VSCode.** Moving the app, the extensions folder
  or the caches out from under a running editor is how you break the editor you are
  sitting in. devbox skips those steps while VSCode is open and tells you to run
  `setup-doctor fix` afterwards.
- **First `code` after a wipe**: the shim rebuilds VSCode before starting it, so it
  takes about half a minute instead of failing.
- **Rootless docker has no CPU or IO limits** unless the machine delegates those
  controllers (it usually does not). `--cpus` and `--memory` may be ignored. Dev
  containers do not care; remember it if you benchmark.
- **Tuning:** every setting in `config.sh` is an environment variable. To change one
  on one machine, export it in `~/.bashrc` **before** the hook:

  ```bash
  export VS_DOCKER_MIN_GB=10            # need 10 GB free to pick a store
  export VS_GOINFRE="/goinfre/$USER"    # campus-specific paths
  export VS_DOCKER_MODE=system          # do not use your own docker on this box
  export VS_CACHE_TARBALL=0             # keep the VSCode download off your home
  ```
