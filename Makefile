# Makefile — convenience wrapper around the school VSCode/Docker setup.
# Run `make` (or `make help`) to list targets.

SHELL := /bin/bash
.DEFAULT_GOAL := help

SETUP_HOME   ?= $(HOME)/.config/vscode-setup
STATE_DIR    := $(HOME)/.local/state/vscode-setup
VS_INSTALLER := $(HOME)/vsCodeInstaller
ZSHRC        := $(HOME)/.zshrc

# Prefer the installed copy; fall back to this repo (so targets work pre-install).
RUN_HOME := $(shell [ -f "$(SETUP_HOME)/config.sh" ] && echo "$(SETUP_HOME)" || echo "$(CURDIR)")
DOCTOR   := VS_SETUP_HOME="$(RUN_HOME)" "$(RUN_HOME)/bin/setup-doctor"
ENSURE   := VS_SETUP_HOME="$(RUN_HOME)" "$(RUN_HOME)/ensure.sh"
DEVBOX   := VS_SETUP_HOME="$(RUN_HOME)" "$(RUN_HOME)/bin/devbox"

.PHONY: help install reinstall provision fix doctor status update logs reset \
        shell check uninstall purge

help: ## Show this help
	@echo "School dev setup — usage: make <target>"
	@echo "  (running from: $(RUN_HOME))"
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

install: ## One-time: copy into ~/.config, hook zsh, provision this machine
	@./install.sh

reinstall: ## Re-copy scripts + re-provision (after editing or git pull)
	@./install.sh

provision: ## Repair only what this machine is missing (idempotent, fast)
	@$(ENSURE)

fix: ## Force a full re-provision regardless of health
	@$(ENSURE) --force

doctor: ## Full status: space, VSCode, docker mode, data-root, hook
	@$(DOCTOR) report

status: doctor ## Alias for 'doctor'

update: ## Download the latest VSCode into ~/vsCodeInstaller
	@$(DOCTOR) update

logs: ## Follow the setup log
	@$(DOCTOR) logs

reset: ## Forget state; next login rebuilds from scratch
	@$(DOCTOR) reset

shell: ## Open a home-mounted throwaway container shell (devbox)
	@$(DEVBOX) shell

check: ## Syntax-check every script + validate template JSON (no install needed)
	@fail=0; \
	for f in config.sh lib/*.sh ensure.sh login.sh install.sh bin/devbox bin/setup-doctor; do \
	  if bash -n "$$f"; then echo "ok   $$f"; else echo "FAIL $$f"; fail=1; fi; \
	done; \
	for j in templates/devcontainer/*/devcontainer.json; do \
	  if command -v python3 >/dev/null 2>&1 && python3 -c "import json,sys; json.load(open('$$j'))" 2>/dev/null; then \
	    echo "ok   $$j"; else echo "FAIL $$j"; fail=1; fi; \
	done; \
	if [ "$$fail" = 0 ]; then echo "all good"; fi; exit $$fail

uninstall: ## Remove the zsh hook + installed scripts (keeps VSCode & docker data)
	@[ -f "$(ZSHRC)" ] && cp "$(ZSHRC)" "$(ZSHRC).bak" || true
	@[ -f "$(ZSHRC)" ] && sed -i '/# >>> vscode-setup >>>/,/# <<< vscode-setup <<</d' "$(ZSHRC)" || true
	@rm -rf "$(SETUP_HOME)"
	@echo "Removed hook from $(ZSHRC) (backup at $(ZSHRC).bak) and $(SETUP_HOME)."
	@echo "VSCode + docker data left intact. Run 'make purge' to delete those too."

purge: ## DANGER: also delete ~/vsCodeInstaller AND all docker data on goinfre/tmp
	@read -r -p "Delete VSCode ($(VS_INSTALLER)) AND all docker data? [y/N] " a; \
	[ "$$a" = y ] || { echo "aborted"; exit 1; }; \
	droot=$$(cat "$(STATE_DIR)/droot" 2>/dev/null); \
	rm -rf "$(VS_INSTALLER)"; echo "removed $(VS_INSTALLER)"; \
	if [ -n "$$droot" ]; then rm -rf "$$droot" && echo "removed docker data at $$droot"; fi; \
	rm -rf "$(STATE_DIR)"; \
	echo "purged."
