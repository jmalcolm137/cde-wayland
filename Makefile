# CDE on Wayland — build entry point.
#
#   make              fetch, build and install the whole stack
#   make fetch        fetch the pinned sources
#   make shim         the libX11 shim, plus libXt and Open Motif
#   make cow          CoW (WITH_RIVER=1 also builds River from source)
#   make tools        tt-portmapper and the other helper programs
#   make cde          CDE libraries, applications, Front Panel and install
#   make test         shim unit/headless tests
#   make test-session nested-session smoke test (needs a Wayland session)
#   make lint         shell syntax, shellcheck, .dt database guard
#   make verify-pins  every pinned revision still resolves upstream
#
# Variables:
#   PREFIX=DIR        install prefix (default ~/.local/cde-wayland)
#   JOBS=N            parallel build jobs (default: nproc)
#   WITH_RIVER=1      build River from source instead of using the distro package

SHELL := /bin/bash
.DEFAULT_GOAL := all

PREFIX     ?= $(HOME)/.local/cde-wayland
JOBS       ?= $(shell nproc 2>/dev/null || echo 4)
WITH_RIVER ?= 0

export CDE_PREFIX := $(PREFIX)
export JOBS

# Resolved exactly as the scripts resolve it (sibling checkout, else the cache).
XLIB_WAYLAND ?= $(shell bash -c 'source scripts/lib.sh; printf %s "$$XLIB_WAYLAND"' 2>/dev/null)
COW_SRC      ?= $(shell bash -c 'source scripts/lib.sh; printf %s "$$COW_SRC"' 2>/dev/null)

.PHONY: all help fetch shim cow tools cde test test-shim test-session lint verify-pins clean

# Ordered explicitly (not as prerequisites) so `make -j` cannot reorder the
# stages: each one depends on the previous.
all:
	@$(MAKE) --no-print-directory fetch
	@$(MAKE) --no-print-directory shim
	@$(MAKE) --no-print-directory cow
	@$(MAKE) --no-print-directory tools
	@$(MAKE) --no-print-directory cde
	@printf '\nInstalled under %s\n' "$(PREFIX)"
	@printf 'Start a session with: CDE_PREFIX=%s scripts/run-session.sh\n' "$(PREFIX)"

help:
	@sed -n '1,17p' Makefile | sed 's/^# \{0,1\}//'

fetch:
	scripts/fetch-sources.sh

shim:
	scripts/build-shim.sh

cow:
	scripts/build-cow.sh $(if $(filter 1,$(WITH_RIVER)),--with-river)

tools:
	scripts/build-tools.sh

cde:
	scripts/build-cde.sh all
	scripts/build-cde.sh programs
	scripts/build-cde.sh doc
	scripts/build-help.sh
	scripts/build-cde.sh panel
	scripts/build-cde.sh install

test: test-shim

test-shim:
	meson setup "$(XLIB_WAYLAND)/build" "$(XLIB_WAYLAND)" \
		--prefix="$(PREFIX)" --buildtype=release --reconfigure
	ninja -C "$(XLIB_WAYLAND)/build"
	meson test -C "$(XLIB_WAYLAND)/build" --print-errorlogs

test-session:
	CDE_PREFIX="$(PREFIX)" scripts/test-nested.sh

lint:
	@for f in scripts/*.sh; do bash -n "$$f" || exit 1; done
	@if command -v shellcheck >/dev/null 2>&1; then shellcheck -S warning scripts/*.sh; \
	  else echo "shellcheck not installed; skipped"; fi
	scripts/test-dt-database.sh

verify-pins:
	scripts/verify-pins.sh

clean:
	@echo "removing build trees (sources are kept)"
	rm -rf "$(PREFIX)/build/cde" "$(COW_SRC)/build" "$(XLIB_WAYLAND)/build"
