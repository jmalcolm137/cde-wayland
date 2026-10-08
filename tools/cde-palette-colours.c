/* cde-palette-colours.c — print the CDE frame/menu colours, for the compositor.
 *
 * CoW draws the window frames, menus and minimized icons, but it is a Wayland
 * compositor and not an X client, so it never sees the palette dtsession's
 * colour server publishes.
 *
 * There are two ways to get at that palette, and the order matters:
 *
 *   1. The resource database names the palette (*0*ColorPalette: Foo.dp) and
 *      the shim relays that database the moment the colour server publishes it,
 *      so the file can be read and its colour sets used at once.  This is what
 *      makes a palette change show up in the frames immediately.
 *   2. Motif's colour object (XmeGetPixelData) holds the active/inactive/primary
 *      pixel sets dtsession computed -- what CDE's own dtwm uses -- but the
 *      colour server only serves them through its selection once it is reopened,
 *      so before that they are one palette behind.  Used as the fallback, and
 *      when the palette file cannot be read.
 *
 *     cde-palette-colours
 *
 * One KEY=#rrggbb per line: active_bg, active_fg, inactive_bg, inactive_fg,
 * primary_bg, primary_fg.
 */
#include <X11/Intrinsic.h>
#include <Xm/Xm.h>
#include <Xm/Label.h>
#include <Xm/ColorObjP.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static Display *dpy;
static Colormap cmap;

static void
emit(const char *key, Pixel p)
{
    XColor c;

    c.pixel = p;
    if (!XQueryColor(dpy, cmap, &c))
        return;
    printf("%s=#%02x%02x%02x\n", key,
           c.red >> 8, c.green >> 8, c.blue >> 8);
}

/* Allocate one of the palette file's "#RRRRGGGGBBBB" colours. */
static Pixel
alloc_palette_colour(const char *spec)
{
    XColor c;
    char buf[16];

    if (spec[0] != '#' || strlen(spec) < 13)
        return 0;
    memcpy(buf, spec, 13);
    buf[13] = 0;
    if (!XParseColor(dpy, cmap, buf, &c))
        return 0;
    if (!XAllocColor(dpy, cmap, &c))
        return 0;
    return c.pixel;
}

/* Derive a legible foreground the way Motif does for every other widget. */
static Pixel
foreground_for(Screen *scr, Pixel bg)
{
    Pixel fg = 0, ts = 0, bs = 0, sc = 0;

    XmGetColors(scr, cmap, bg, &fg, &ts, &bs, &sc);
    return fg;
}

/* Use the palette file named by the (freshly relayed) resource database.
 * Returns 0 when it cannot be read, so the caller can fall back. */
static int
from_palette_file(Screen *scr)
{
    const char *db = XResourceManagerString(dpy);
    const char *p;
    char name[256] = "";
    char path[PATH_MAX];
    char line[128];
    char cols[8][16];
    const char *dirs[3];
    FILE *f = NULL;
    size_t i;
    int n = 0;

    if (!db)
        return 0;
    p = strstr(db, "*0*ColorPalette:");
    if (!p)
        return 0;
    p += strlen("*0*ColorPalette:");
    while (*p == ' ' || *p == '\t')
        p++;
    for (i = 0; *p && *p != '\n' && *p != '\r' && i < sizeof name - 1; i++)
        name[i] = *p++;
    name[i] = 0;
    if (!name[0])
        return 0;

    dirs[0] = dirs[1] = NULL;
    {
        static char instdir[PATH_MAX], homedir[PATH_MAX];
        const char *root = getenv("CDE_ROOT");
        const char *home = getenv("HOME");

        snprintf(instdir, sizeof instdir, "%s/palettes", root ? root : "/usr/dt");
        snprintf(homedir, sizeof homedir, "%s/.dt/palettes", home ? home : ".");
        dirs[0] = instdir;
        dirs[1] = homedir;
        dirs[2] = NULL;
    }
    for (i = 0; dirs[i] && !f; i++) {
        snprintf(path, sizeof path, "%s/%s", dirs[i], name);
        f = fopen(path, "r");
    }
    if (!f)
        return 0;

    while (fgets(line, sizeof line, f) && n < 8) {
        char *s = line;
        while (*s == ' ' || *s == '\t')
            s++;
        if (*s != '#')
            continue;
        for (i = 0; i < sizeof cols[0] - 1 && s[i] && s[i] != '\n' &&
                    s[i] != '\r'; i++)
            cols[n][i] = s[i];
        cols[n][i] = 0;
        n++;
    }
    fclose(f);

    /* CDE's high-colour mapping: set 0 is active, 1 inactive, 4 the one the
     * client area uses. */
    if (n < 5)
        return 0;

    {
        Pixel a = alloc_palette_colour(cols[0]);
        Pixel in = alloc_palette_colour(cols[1]);
        Pixel pr = alloc_palette_colour(cols[4]);

        if (!a || !in || !pr)
            return 0;
        printf("active_bg=#%02lx%02lx%02lx\n",
               (a >> 16) & 0xff, (a >> 8) & 0xff, a & 0xff);
        emit("active_fg", foreground_for(scr, a));
        printf("inactive_bg=#%02lx%02lx%02lx\n",
               (in >> 16) & 0xff, (in >> 8) & 0xff, in & 0xff);
        emit("inactive_fg", foreground_for(scr, in));
        printf("primary_bg=#%02lx%02lx%02lx\n",
               (pr >> 16) & 0xff, (pr >> 8) & 0xff, pr & 0xff);
        emit("primary_fg", foreground_for(scr, pr));
    }
    return 1;
}

int
main(int argc, char **argv)
{
    XtAppContext app;
    Widget top, probe;
    Screen *scr;
    XmPixelSet sets[XmCO_NUM_COLORS];
    int color_use = 0;
    short active = 0, inactive = 0, primary = 0, secondary = 0;
    int i;

    top = XtAppInitialize(&app, "CdePaletteColours", NULL, 0, &argc, argv,
                          NULL, NULL, 0);
    dpy = XtDisplay(top);
    scr = DefaultScreenOfDisplay(dpy);
    cmap = DefaultColormapOfScreen(scr);

    if (from_palette_file(scr))
        return 0;

    /* Fallback: the colour server's pixel sets.  These are only fresh once the
     * colour server has been reopened, so this is not the immediate path. */
    for (i = 0; i < 200; i++) {
        while (XtAppPending(app))
            XtAppProcessEvent(app, XtIMAll);
        XFlush(dpy);
        usleep(10000);
    }

    if (XmeGetPixelData(XScreenNumberOfScreen(scr), &color_use, sets,
                        &active, &inactive, &primary, &secondary)) {
        emit("active_bg", sets[active].bg);
        emit("active_fg", sets[active].fg);
        emit("inactive_bg", sets[inactive].bg);
        emit("inactive_fg", sets[inactive].fg);
        emit("primary_bg", sets[primary].bg);
        emit("primary_fg", sets[primary].fg);
        return 0;
    }

    /* No colour server and no palette file: derive from the resource database
     * the plain Motif way, which is what XmGetColors() does for other widgets. */
    probe = XtVaCreateWidget("probe", xmLabelWidgetClass, top, NULL);
    if (probe) {
        Pixel bg = 0, fg = 0, ts = 0, bs = 0, sc = 0;

        XtVaGetValues(probe, XmNbackground, &bg, XmNforeground, &fg, NULL);
        XmGetColors(scr, cmap, bg, &fg, &ts, &bs, &sc);
        emit("active_bg", bg);
        emit("active_fg", fg);
        emit("inactive_bg", bs);
        emit("inactive_fg", fg);
        emit("primary_bg", bg);
        emit("primary_fg", fg);
        return 0;
    }
    return 1;
}
