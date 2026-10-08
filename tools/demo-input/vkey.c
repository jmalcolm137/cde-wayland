#define _GNU_SOURCE
/* vkey — type text / press keys in the nested session via
 * zwp_virtual_keyboard_v1.  The keymap is composed with xkbcommon so the
 * keycodes are whatever the current layout says.
 *
 * usage: vkey [-d MS] TEXT...
 *   \n  Return   \t  Tab   \e  Escape
 */
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/time.h>
#include "vkbd.h"

static struct wl_display *dpy = NULL;
static struct zwp_virtual_keyboard_manager_v1 *kmgr = NULL;
static struct wl_seat *seat = NULL;
static struct zwp_virtual_keyboard_v1 *vkbd = NULL;
static struct xkb_keymap *keymap = NULL;
static uint32_t shift_mask = 1;

static void reg_global(void *d, struct wl_registry *r, uint32_t name,
                       const char *iface, uint32_t ver) {
    (void)d; (void)ver;
    if (!strcmp(iface, zwp_virtual_keyboard_manager_v1_interface.name))
        kmgr = wl_registry_bind(r, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
    else if (!strcmp(iface, wl_seat_interface.name) && !seat)
        seat = wl_registry_bind(r, name, &wl_seat_interface, 1);
}
static void reg_remove(void *d, struct wl_registry *r, uint32_t n) { (void)d; (void)r; (void)n; }
static const struct wl_registry_listener rl = { reg_global, reg_remove };

static uint32_t now_ms(void) {
    struct timeval tv; gettimeofday(&tv, NULL);
    return (uint32_t)(tv.tv_sec * 1000 + tv.tv_usec / 1000);
}

static int find_key(xkb_keysym_t ks, uint32_t *keycode, int *shift) {
    for (uint32_t kc = 9; kc < 256; kc++) {
        const xkb_keysym_t *syms = NULL;
        int n = xkb_keymap_key_get_syms_by_level(keymap, kc, 0, 0, &syms);
        for (int i = 0; i < n; i++) if (syms[i] == ks) { *keycode = kc; *shift = 0; return 0; }
        n = xkb_keymap_key_get_syms_by_level(keymap, kc, 0, 1, &syms);
        for (int i = 0; i < n; i++) if (syms[i] == ks) { *keycode = kc; *shift = 1; return 0; }
    }
    return -1;
}

static int cur_shift = 0;
static void tap(xkb_keysym_t ks, int delay_ms) {
    uint32_t kc; int sh;
    if (find_key(ks, &kc, &sh) < 0) { fprintf(stderr, "vkey: no key for keysym U+%04X\n", ks); return; }
    if (sh != cur_shift) {
        zwp_virtual_keyboard_v1_modifiers(vkbd, 0, sh ? shift_mask : 0, 0, 0, 0);
        cur_shift = sh;
        wl_display_flush(dpy);
        usleep(8000);
    }
    uint32_t t = now_ms();
    uint32_t sc = kc >= 8 ? kc - 8 : kc;   /* xkb keycode -> evdev scancode */
    zwp_virtual_keyboard_v1_key(vkbd, t, sc, 1);
    zwp_virtual_keyboard_v1_key(vkbd, t, sc, 0);
    wl_display_flush(dpy);
    if (delay_ms) usleep((useconds_t)delay_ms * 1000);
}

int main(int argc, char **argv) {
    int delay = 25, ai = 1;
    if (argc > 2 && !strcmp(argv[1], "-d")) { delay = atoi(argv[2]); ai = 3; }
    if (ai >= argc) { fprintf(stderr, "usage: vkey [-d MS] TEXT...\n"); return 2; }

    dpy = wl_display_connect(NULL);
    if (!dpy) { fprintf(stderr, "vkey: no display\n"); return 1; }
    struct wl_registry *reg = wl_display_get_registry(dpy);
    wl_registry_add_listener(reg, &rl, NULL);
    wl_display_roundtrip(dpy);
    if (!kmgr || !seat) { fprintf(stderr, "vkey: no virtual keyboard manager / seat\n"); return 1; }

    vkbd = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(kmgr, seat);

    struct xkb_context *ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct xkb_rule_names names = { .rules = "evdev", .model = "pc105",
                                    .layout = "us", .variant = NULL, .options = NULL };
    keymap = xkb_keymap_new_from_names(ctx, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
    if (!keymap) { fprintf(stderr, "vkey: no keymap\n"); return 1; }
    shift_mask = 1u << xkb_keymap_mod_get_index(keymap, XKB_MOD_NAME_SHIFT);

    char *str = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
    size_t len = strlen(str) + 1;
    int fd = memfd_create("keymap", MFD_CLOEXEC);
    if (fd < 0 || write(fd, str, len) != (ssize_t)len) { fprintf(stderr, "vkey: keymap fd\n"); return 1; }
    zwp_virtual_keyboard_v1_keymap(vkbd, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, (uint32_t)len);
    close(fd);
    wl_display_roundtrip(dpy);
    usleep(30000);

    for (int a = ai; a < argc; a++) {
        for (const char *p = argv[a]; *p; p++) {
            xkb_keysym_t ks;
            if (*p == '\\' && p[1]) {
                p++;
                if (*p == 'n') ks = XKB_KEY_Return;
                else if (*p == 't') ks = XKB_KEY_Tab;
                else if (*p == 'e') ks = XKB_KEY_Escape;
                else if (*p == 'b') ks = XKB_KEY_BackSpace;
                else ks = (xkb_keysym_t)(unsigned char)*p;
            } else if (*p == ' ') {
                ks = XKB_KEY_space;
            } else {
                ks = (xkb_keysym_t)(unsigned char)*p;
            }
            tap(ks, delay);
        }
        if (a + 1 < argc) tap(XKB_KEY_space, delay);
    }
    wl_display_flush(dpy);
    usleep(50000);
    return 0;
}
