# Makefile for cde-wayland C helper tools.
#
#   make base PREFIX=...   pre-CDE tools (tt-portmapper)
#   make cde  PREFIX=...   CDE/Motif/X11 tools (cde-wsm, cde-confirm,
#                          cde-palette-colours, xrdb)
#   make all  PREFIX=...   everything

CC     ?= gcc
CFLAGS ?= -O2 -g -Wall -Wextra
PREFIX ?= $(HOME)/.local/cde-wayland
BINDIR := $(PREFIX)/bin

TIRPC_CFLAGS := $(shell pkg-config --cflags libtirpc 2>/dev/null || echo -I/usr/include/tirpc)
TIRPC_LIBS   := $(shell pkg-config --libs libtirpc 2>/dev/null || echo -ltirpc)

# The CDE tools are built by install-panel-data.sh, before build-cde.sh
# install has put the Dt headers and libraries under $(PREFIX)/dt: take them
# from the CDE build tree's exports when there is one (first, so a fresh build
# wins over a stale install).
CDE_BUILD ?=
CDE_EXPORTS_INC := $(if $(CDE_BUILD),-I$(CDE_BUILD)/exports/include)
CDE_EXPORTS_LIB := $(if $(CDE_BUILD),-L$(CDE_BUILD)/exports/lib)

CDE_INC   := $(CDE_EXPORTS_INC) -I$(PREFIX)/dt/include -I$(PREFIX)/include -I/usr/include/tirpc
CDE_LIB   := $(CDE_EXPORTS_LIB) -L$(PREFIX)/dt/lib -L$(PREFIX)/lib
CDE_RPATH := -Wl,-rpath,$(PREFIX)/lib:$(PREFIX)/dt/lib

.PHONY: all base cde clean

all: base cde

base: $(BINDIR)/tt-portmapper

cde: $(BINDIR)/cde-wsm $(BINDIR)/cde-confirm $(BINDIR)/cde-palette-colours $(BINDIR)/xrdb

$(BINDIR):
	mkdir -p "$@"

$(BINDIR)/tt-portmapper: tt-portmapper.c | $(BINDIR)
	$(CC) $(CFLAGS) $(TIRPC_CFLAGS) -o "$@" "$<" $(TIRPC_LIBS)

$(BINDIR)/cde-wsm: cde-wsm.c | $(BINDIR)
	$(CC) $(CFLAGS) $(CDE_INC) $(CDE_LIB) -o "$@" "$<" -lDtSvc -ltt -lXm -lXt -lX11 $(CDE_RPATH)

$(BINDIR)/cde-confirm: cde-confirm.c | $(BINDIR)
	$(CC) $(CFLAGS) $(CDE_INC) $(CDE_LIB) -o "$@" "$<" -lXm -lXt -lX11 $(CDE_RPATH)

$(BINDIR)/cde-palette-colours: cde-palette-colours.c | $(BINDIR)
	$(CC) $(CFLAGS) $(CDE_INC) $(CDE_LIB) -o "$@" "$<" -lXm -lXt -lX11 $(CDE_RPATH)

$(BINDIR)/xrdb: xrdb.c | $(BINDIR)
	$(CC) $(CFLAGS) -I$(PREFIX)/include -L$(PREFIX)/lib -o "$@" "$<" -lX11 -Wl,-rpath,$(PREFIX)/lib

clean:
	rm -f $(BINDIR)/tt-portmapper $(BINDIR)/cde-wsm $(BINDIR)/cde-confirm \
	      $(BINDIR)/cde-palette-colours $(BINDIR)/xrdb
