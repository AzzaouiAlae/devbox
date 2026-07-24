# devbox — VSCode + Docker that fit in your 5 GB school home

A one-time install that lets you use **VSCode Dev Containers** on 1337 / 42
machines without ever blowing past your tiny home-directory quota. Set it up
once; from then on it repairs itself automatically every time you log in, on
any machine, with **no root and no manual steps**.

---

## The problem this solves

On school machines your storage is split in a way that fights against normal dev
tools:

| Location | Size | Survives a machine switch? |
|---|---|---|
| Your home (`~`) | **~5 GB** | ✅ yes (it's on NFS, follows you everywhere) |
| `/goinfre/$USER` | ~30 GB | ❌ no (local to that one machine, wiped when you leave) |
| `/tmp/$USER` | ~256 GB | ❌ no (local, wiped) |

Docker images, containers, and VSCode's heavier extensions can easily eat
**10–20 GB**. If those land in your home you hit the 5 GB wall within a day. But
if you just dump everything on `/goinfre`, it all vanishes the moment you sit at
a different machine.

**The trick:** keep the small stuff that must persist (your code, the VSCode
app, a few config files) in your 5 GB home, and put all the big, disposable
stuff (Docker data, extensions) on `/goinfre` or `/tmp`. Then rebuild the big
stuff automatically whenever you log into a fresh machine. That's the whole
idea — this project just makes it happen for you.

---

## What goes where

| Thing | Where it lives | Why there |
|---|---|---|
| VSCode itself | `~/vsCodeInstaller/` (your 5 GB home) | Must persist across machines; it's ~1 GB |
| These scripts + state | `~/.config/vscode-setup/`, `~/.local/state/vscode-setup/` | Tiny, must persist |
| Your project code | Your home | Small, must never be lost |
| Docker data (images, containers, volumes) | `/goinfre/$USER/docker` → `/tmp/$USER/docker` | Huge & disposable — **never** your home |
| VSCode extensions on the host | symlinked to `/goinfre/$USER/vscode-extensions` → `/tmp/$USER` | AI assistants / language packs run to hundreds of MB |
| Project extensions (C#, Angular…) | **inside the dev container** (also on goinfre/tmp) | Off your home entirely |

**The one rule the setup enforces on every login:** Docker's data must never
sit under your home. It checks where Docker is storing data; if that's under
`~`, it relocates Docker (as rootless) onto goinfre/tmp; if it's already on
local disk, it leaves it alone.

---

## Install (once per account)

Copy this folder onto a school machine (git clone, USB, scp — whatever), then:

```bash
cd devbox
make install        # same as: ./install.sh
```

That does three things:

1. Copies itself into `~/.config/vscode-setup/` (your persistent home).
2. Adds a small, self-contained hook to your `~/.zshrc`.
3. Provisions the machine you're on right now (installs VSCode, sets up Docker
   storage, etc.).

Because both the hook and the scripts live in your persistent home, **every
future login on every machine** re-runs the same health check and rebuilds
whatever that particular machine is missing. You install once; it follows you
forever.

Open a new terminal (or run `source ~/.zshrc`) so the `devbox` command lands on
your `PATH`.

---

## Daily use

Pick a project folder, scaffold a dev container for it, and open it:

```bash
cd ~/projects/my-api
devbox init dotnet     # pick one: dotnet | angular | cpp | base
devbox open            # opens VSCode in this folder
```

`devbox init` writes a ready-made `.devcontainer/` into your project. Then in
VSCode, run **Dev Containers: Reopen in Container** (or click the blue `><`
corner → *Reopen in Container*). The language extensions install *inside* the
container, on goinfre/tmp — not in your home.

### Skip the "Reopen in Container" click

To jump straight into the container without opening a normal window first:

```bash
devbox container .     # opens the folder already attached to its container
```

### The `devbox` commands

| Command | What it does |
|---|---|
| `devbox init <type>` | Scaffold `.devcontainer/` (`dotnet`, `angular`, `cpp`, or `base`) |
| `devbox open [dir]` | Open a folder in VSCode (then Reopen in Container) |
| `devbox container [dir]` | Open a folder **directly** in its dev container |
| `devbox up [image]` | Start a quick throwaway container with your home mounted (no VSCode) |
| `devbox shell` | Drop into a shell in that throwaway container |
| `devbox down` | Stop & remove the throwaway container |
| `devbox where` | Show where Docker is currently storing its data |

---

## Check & repair

Run these from the repo (`make` on its own lists them all), or use
`setup-doctor <action>` from anywhere once it's on your PATH:

| Command | What it does |
|---|---|
| `make doctor` | Full status: free space, VSCode, Docker mode, data-root, hook |
| `make fix` | Force a full re-provision, even if things look healthy |
| `make update` | Pull the latest VSCode |
| `make logs` | Follow the setup log live |
| `make reset` | Forget saved state; next login rebuilds from scratch |
| `make check` | Syntax-check the scripts + validate the templates (no install needed) |
| `make uninstall` | Remove the zsh hook + scripts (keeps VSCode & Docker data) |
| `make purge` | ⚠️ Also delete VSCode **and** all Docker data |

---

## How it stays fast

You don't want every new terminal to pause while it checks Docker. So the work
is split:

- **`login.sh`** runs on *every* shell but only does the cheap thing: put
  `devbox` / `code` / `docker` on your PATH. Instant.
- **`ensure.sh`** does the heavy checking (VSCode, Docker storage, extensions).
  It runs **only** when the machine looks unprovisioned or when the last
  successful check is older than an hour (`VS_HEALTH_TTL_MIN`, default 60).

So the first login on a fresh machine takes a moment to rebuild everything, but
every terminal you open after that is immediate.

---

## Tuning (optional)

Every setting has a sensible default and can be overridden with an environment
variable — see `config.sh`. To change something on one machine, export it in
`~/.zshrc` **before** the hook:

```bash
export VS_DOCKER_MIN_GB=10           # require 10 GB free before using a location
export VS_GOINFRE="/goinfre/$USER"   # campus-specific paths
export VS_TMP="/tmp/$USER"
```

---

## Good to know

- **goinfre / tmp are wiped when you switch machines.** That's by design here:
  Docker images get re-pulled and containers rebuilt on the new machine. Because
  your `.devcontainer/` lives in your home, the rebuild reinstalls every tool
  and extension for you automatically — you just wait for it once.
- **The same applies to `~/.vscode/extensions`.** It's stored on goinfre/tmp
  too, so any host extension — including ones you install by hand, not just the
  ones this setup manages — is gone after a machine switch and reinstalls fresh
  the next time you need it.
- **`~/.config/Code/CachedExtensionVSIXs`** (VSCode's cache of downloaded
  `.vsix` files) is cleared automatically during provisioning. It's pure cache —
  safe to lose, and it otherwise grows forever.
- **Rootless Docker.** If your machine only offers Docker as a shared system
  daemon that stores data under your home, the setup switches you to *rootless*
  Docker so the data lands on goinfre/tmp instead. This needs
  `dockerd-rootless-setuptool.sh` (ships with Docker ≥ 20.10). `setup-doctor`
  tells you which mode you're in.
- **No root, anywhere.** Nothing here needs sudo.
