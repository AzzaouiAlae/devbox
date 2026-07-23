# School dev setup — VSCode + Docker on goinfre/tmp, auto-installed at login

Solves the 1337/42 problem: your login **session only has ~5 G**, but the
machine has **goinfre (~30 G)** and **/tmp (~256 G)** local disk. Those local
disks are wiped when you switch machines, so this setup keeps the small,
*persistent* definitions in your 5 G home and rebuilds the heavy bytes on
goinfre/tmp **automatically at every login** — no root, no manual steps.

## What it does

| Thing | Where it lives | Why |
|---|---|---|
| VSCode (latest stable) | `~/vsCodeInstaller/VSCode-linux-x64` (your 5 G home, ~350 MB) | Persists across machines via NFS |
| These scripts + state | `~/.config/vscode-setup`, `~/.local/state/vscode-setup` | Tiny, persistent |
| Docker data (images/containers/volumes) | `/goinfre/$USER/docker` → falls back to `/tmp/$USER/docker` | Big & ephemeral; **never** your 5 G home |
| Project source code | Your home, inside projects | Small, must persist |
| **Extensions (C#, Angular, …)** | **Inside the dev container** (on goinfre/tmp) | Off your 5 G home |

The one invariant enforced on every login: **docker data must never sit under
`$HOME`.** The installer reads `docker info`; if the data-root is under your
home it relocates docker (rootless) onto goinfre/tmp; if it is already on local
disk it leaves it alone.

## Install (once per account — it follows you to every machine after that)

Copy this folder to a school machine (git clone, USB, or scp), then:

```bash
cd dockerSetup
make install          # or: ./install.sh
```

That copies itself into `~/.config/vscode-setup`, adds a guarded hook to
`~/.zshrc`, and provisions the current machine immediately. Because the hook and
the scripts live in your persistent home, **every future login on any machine**
runs the same check and repairs whatever that machine is missing.

Open a new terminal (or `source ~/.zshrc`) afterwards.

## Daily use

```bash
cd ~/projects/my-api
devbox init dotnet      # or: angular | cpp | base   -> writes ./.devcontainer/
devbox open             # opens VSCode here
```

Then in VSCode: **Dev Containers: Reopen in Container**. The C#/Angular
extensions install *inside* the container (on goinfre/tmp), not your home.

Quick throwaway shell with your whole home mounted (no VSCode):

```bash
devbox up && devbox shell
```

## Check / repair

Use the Makefile (run `make` for the full list) or the tools directly:

```bash
make doctor       # full status: space, vscode, docker mode, data-root, hook
make fix          # force a full re-provision
make update       # pull the latest VSCode
make logs         # follow the setup log
make reset        # forget state; next login rebuilds from scratch
make check        # syntax-check scripts + validate templates (no install needed)
make uninstall    # remove the zsh hook + scripts (keeps VSCode & docker data)
make purge        # DANGER: also delete VSCode + all docker data
```

The same actions are available as `setup-doctor <report|fix|update|logs|reset>`
once the hook has put it on your `PATH`.

## How the login flow stays fast

`login.sh` (sourced by `~/.zshrc`) only exports PATH/`DOCKER_HOST` on every
shell. The heavier `ensure.sh` runs **only** when the health marker is older
than `VS_HEALTH_TTL_MIN` (default 60 min) or the machine is unprovisioned — so
opening extra terminals is instant, but the first login on a fresh machine
rebuilds docker storage before you need it.

## Tuning

Everything is overridable via env vars (see `config.sh`), e.g. put this before
the hook in `~/.zshrc` to change the fallback thresholds:

```bash
export VS_DOCKER_MIN_GB=10          # need 10G free before using a location
export VS_GOINFRE="/goinfre/$USER"  # campus-specific paths
export VS_TMP="/tmp/$USER"
```

## Notes / limits

- goinfre and /tmp are **per-machine and wiped on switch** — docker images are
  re-pulled and containers rebuilt on a new machine. That is unavoidable given
  the 5 G persistent quota; this setup just makes it automatic. Because your
  `.devcontainer/` lives in your home, the rebuild reinstalls all tools and
  extensions for you.
- If your campus provides docker only as a shared **system** daemon whose
  storage is under `$HOME`, the installer switches you to **rootless** docker so
  the data lands on goinfre/tmp. Requires `dockerd-rootless-setuptool.sh` to be
  present (ships with Docker ≥ 20.10). `setup-doctor` will tell you which mode
  you are in.
- No root is used anywhere.
