# Makefile — convenience wrapper around the devbox setup.
# Run `make` (or `make help`) to list targets.

SHELL := /bin/bash
.DEFAULT_GOAL := help

SETUP_HOME ?= $(HOME)/.config/vscode-setup
STATE_DIR  := $(HOME)/.local/state/vscode-setup
CACHE_DIR  := $(HOME)/.cache/devbox
LEGACY_VS  := $(HOME)/vsCodeInstaller

# Prefer the installed copy; fall back to this repo (so targets work pre-install).
RUN_HOME := $(shell [ -f "$(SETUP_HOME)/config.sh" ] && echo "$(SETUP_HOME)" || echo "$(CURDIR)")
DOCTOR   := VS_SETUP_HOME="$(RUN_HOME)" "$(RUN_HOME)/bin/setup-doctor"
ENSURE   := VS_SETUP_HOME="$(RUN_HOME)" "$(RUN_HOME)/ensure.sh"
DEVBOX   := VS_SETUP_HOME="$(RUN_HOME)" "$(RUN_HOME)/bin/devbox"

.PHONY: help install reinstall provision fix doctor status update logs reset \
        goinfre where ext-save shell check smoke uninstall purge

help: ## Show this help
	@echo "devbox — usage: make <target>"
	@echo "  (running from: $(RUN_HOME))"
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

install: ## One-time: copy into ~/.config, hook bash+zsh, provision this machine
	@./install.sh

reinstall: install ## Re-copy scripts + re-provision (after editing or git pull)

provision: ## Repair only what this machine is missing (idempotent, fast)
	@$(ENSURE)

fix: ## Force a full re-provision regardless of health
	@$(ENSURE) --force --interactive

doctor: ## Full status: storage, VSCode, your docker, hooks
	@$(DOCTOR) report

status: doctor ## Alias for 'doctor'

where: ## Short version: store, docker mode, socket, pinned versions
	@$(DEVBOX) where

update: ## Download the latest VSCode and re-extract it onto the store
	@$(DOCTOR) update

goinfre: ## Create /goinfre/$$USER on a non-school machine (asks for sudo once)
	@$(DEVBOX) goinfre

ext-save: ## Save your current extension list (survives a machine switch)
	@$(DEVBOX) ext save

logs: ## Follow the setup log
	@$(DOCTOR) logs

reset: ## Forget state + store choice; next login rebuilds
	@$(DOCTOR) reset

shell: ## Open a home-mounted throwaway container shell
	@$(DEVBOX) shell

check: ## Syntax-check every script + validate the templates (no install needed)
	@fail=0; \
	for f in config.sh lib/*.sh ensure.sh login.sh install.sh bin/devbox bin/setup-doctor bin/selftest; do \
	  if bash -n "$$f"; then echo "ok   $$f"; else echo "FAIL $$f"; fail=1; fi; \
	done; \
	for d in templates/devcontainer/*/; do \
	  j="$$d/devcontainer.json"; f2="$$d/Dockerfile"; \
	  if python3 -c "import json,sys; json.load(open('$$j'))" 2>/dev/null; then echo "ok   $$j"; \
	  else echo "FAIL $$j"; fail=1; fi; \
	  if [ -f "$$f2" ]; then echo "ok   $$f2"; else echo "FAIL $$f2 (missing)"; fail=1; fi; \
	done; \
	if [ "$$fail" = 0 ]; then echo "all good"; fi; exit $$fail

smoke: ## Run the commands for real and check what they produce (catches what 'check' cannot)
	@VS_SETUP_HOME="$(RUN_HOME)" "$(RUN_HOME)/bin/selftest"

uninstall: ## Remove the login hooks + installed scripts (keeps VSCode & docker data)
	@for rc in $(HOME)/.bashrc $(HOME)/.zshrc; do \
	  [ -f "$$rc" ] || continue; cp "$$rc" "$$rc.bak"; \
	  sed -i '/# >>> vscode-setup >>>/,/# <<< vscode-setup <<</d' "$$rc"; \
	  echo "unhooked $$rc (backup at $$rc.bak)"; \
	done
	@rm -f $(HOME)/.config/environment.d/10-devbox.conf
	@rm -rf "$(SETUP_HOME)"
	@echo "VSCode + docker data left intact. Run 'make purge' to delete those too."

purge: ## DANGER: also delete the store (VSCode, extensions, docker data) + caches
	@store=$$(cat "$(STATE_DIR)/store" 2>/dev/null); \
	read -r -p "Delete the whole store ($$store) AND $(CACHE_DIR)? [y/N] " a; \
	[ "$$a" = y ] || { echo "aborted"; exit 1; }; \
	if [ -n "$$store" ]; then \
	  rm -rf "$$store/vscode" "$$store/vscode-extensions" "$$store/vscode-cache" "$$store/docker"; \
	  echo "emptied $$store"; \
	fi; \
	rm -rf "$(CACHE_DIR)" "$(LEGACY_VS)" "$(HOME)/.vscode/extensions" "$(STATE_DIR)"; \
	echo "purged."
