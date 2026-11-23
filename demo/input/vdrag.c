/* vdrag — inject a slow drag via zwlr_virtual_pointer: motion, settle, press,
 * settle, several motion steps, settle, release.  The CDE icon gadget needs
 * the press to register before the motion moves off the icon. */
#include <wayland-client.h>
#include <linux/input.h>
#include "vptr.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static struct zwlr_virtual_pointer_manager_v1 *mgr = NULL;
static struct wl_seat *seat = NULL;
static void reg_global(void *d, struct wl_registry *r, uint32_t name,
                       const char *iface, uint32_t ver) {
    (void)d; (void)ver;
    if (!strcmp(iface, zwlr_virtual_pointer_manager_v1_interface.name))
        mgr = wl_registry_bind(r, name, &zwlr_virtual_pointer_manager_v1_interface, 2);
    else if (!strcmp(iface, wl_seat_interface.name) && !seat)
        seat = wl_registry_bind(r, name, &wl_seat_interface, 1);
}
static void reg_remove(void *d, struct wl_registry *r, uint32_t n) { (void)d;(void)r;(void)n; }
static const struct wl_registry_listener rl = { reg_global, reg_remove };

int main(int argc, char **argv) {
    if (argc < 5) { fprintf(stderr, "usage: %s X1 Y1 X2 Y2 [W H]\n", argv[0]); return 2; }
    int x1 = atoi(argv[1]), y1 = atoi(argv[2]);
    int x2 = atoi(argv[3]), y2 = atoi(argv[4]);
    int w = argc > 5 ? atoi(argv[5]) : 1280, h = argc > 6 ? atoi(argv[6]) : 720;
    struct wl_display *dpy = wl_display_connect(NULL);
    if (!dpy) { fprintf(stderr, "no display\n"); return 1; }
    struct wl_registry *reg = wl_display_get_registry(dpy);
    wl_registry_add_listener(reg, &rl, NULL);
    wl_display_roundtrip(dpy);
    if (!mgr) { fprintf(stderr, "no virtual pointer manager\n"); return 1; }
    struct zwlr_virtual_pointer_v1 *vp =
        zwlr_virtual_pointer_manager_v1_create_virtual_pointer(mgr, seat);

    zwlr_virtual_pointer_v1_motion_absolute(vp, 0, x1, y1, w, h);
    zwlr_virtual_pointer_v1_frame(vp);
    wl_display_flush(dpy); usleep(250000);

    zwlr_virtual_pointer_v1_button(vp, 0, BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED);
    zwlr_virtual_pointer_v1_frame(vp);
    wl_display_flush(dpy); usleep(350000);

    for (int i = 1; i <= 8; i++) {
        int x = x1 + (x2 - x1) * i / 8;
        int y = y1 + (y2 - y1) * i / 8;
        zwlr_virtual_pointer_v1_motion_absolute(vp, 0, x, y, w, h);
        zwlr_virtual_pointer_v1_frame(vp);
        wl_display_flush(dpy); usleep(80000);
    }
    usleep(250000);
    zwlr_virtual_pointer_v1_button(vp, 0, BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED);
    zwlr_virtual_pointer_v1_frame(vp);
    wl_display_flush(dpy); usleep(250000);
    return 0;
}
