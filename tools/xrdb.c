/* xrdb.c — load or merge resources into RESOURCE_MANAGER, for the shim.
 *
 * dtsession restores the session's resources by running dtsession_res, which
 * pipes CDE's sys.resources (and ~/.Xdefaults) into xrdb.  There is no X server
 * keeping a resource database here -- each client is its own server -- so the
 * shim synthesises RESOURCE_MANAGER from files and relays it between processes
 * (see xlib-wayland src/xlib/xresources.c and smprops.c).  Building this xrdb
 * against the shim makes it write to that property, which the shim publishes to
 * the shared store, so the resources reach every client that starts afterwards
 * -- which is what xrdb does in a normal session, where clients read the
 * property once, at startup.
 *
 *     xrdb [-quiet] [-load|-merge] [-nocpp] [-Dname[=value]] [-Uname] [-Idir]
 *          [-file file]... [-query|-o]
 *
 * Reads stdin unless -file is given.  Like xrdb, the input is run through cpp
 * (the CDE resource files carry #if branches) unless -nocpp is given.
 */
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAXFILES 32

static void
usage(void)
{
    fprintf(stderr, "usage: xrdb [-quiet] [-load|-merge] [-nocpp] "
                    "[-Dname[=value]] [-Uname] [-Idir] [-file file]... "
                    "[-query|-o]\n");
}

/* Run the input through cpp, returning its output (malloc'd).  -traditional-cpp
 * is used because the resource files contain values with quotes and backslashes
 * that the modern preprocessor would rewrite. */
static char *
preprocess(const char *input, char *const *deflist, int ndef)
{
    char tmp[] = "/tmp/xrdb-in-XXXXXX";
    int fd = mkstemp(tmp);
    FILE *p;
    char *out = NULL, buf[4096];
    size_t len = 0, cap = 0;
    char cmd[4096];
    int n;

    if (fd < 0)
        return NULL;
    if (write(fd, input, strlen(input)) < 0) {
        close(fd);
        unlink(tmp);
        return NULL;
    }
    close(fd);

    n = snprintf(cmd, sizeof cmd, "cpp -traditional-cpp -P");
    for (int i = 0; i < ndef && n > 0 && n < (int) sizeof cmd; i++)
        n += snprintf(cmd + n, sizeof cmd - n, " '%s'", deflist[i]);
    snprintf(cmd + n, sizeof cmd - n, " '%s' 2>/dev/null", tmp);

    p = popen(cmd, "r");
    if (p) {
        while (fgets(buf, sizeof buf, p)) {
            size_t l = strlen(buf);
            if (len + l + 1 > cap) {
                cap = (len + l + 1) * 2;
                char *t = realloc(out, cap);
                if (!t) { free(out); out = NULL; break; }
                out = t;
            }
            memcpy(out + len, buf, l);
            len += l;
            out[len] = 0;
        }
        pclose(p);
    }
    unlink(tmp);
    return out;
}

int
main(int argc, char **argv)
{
    int quiet = 0, merge = 0, nocpp = 0, query = 0;
    char *files[MAXFILES];
    int nfiles = 0;
    char *cppargs[64];
    int ncpp = 0;
    Display *dpy;
    Window root;
    Atom rm;
    char *text = NULL;
    size_t len = 0, cap = 0;
    char *existing = NULL;
    int i;

    for (i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (strcmp(a, "-quiet") == 0 || strcmp(a, "-n") == 0)
            quiet = 1;
        else if (strcmp(a, "-load") == 0)
            merge = 0;
        else if (strcmp(a, "-merge") == 0)
            merge = 1;
        else if (strcmp(a, "-nocpp") == 0)
            nocpp = 1;
        else if (strcmp(a, "-query") == 0 || strcmp(a, "-o") == 0)
            query = 1;
        else if (strcmp(a, "-file") == 0) {
            if (++i >= argc) { usage(); return 1; }
            if (nfiles < MAXFILES)
                files[nfiles++] = argv[i];
        } else if (a[0] == '-' &&
                   (a[1] == 'D' || a[1] == 'U' || a[1] == 'I')) {
            if (ncpp < (int) (sizeof cppargs / sizeof cppargs[0]))
                cppargs[ncpp++] = argv[i];
        } else if (strcmp(a, "-help") == 0 || strcmp(a, "--help") == 0) {
            usage();
            return 0;
        } else if (strcmp(a, "-display") == 0) {
            i++;    /* XOpenDisplay takes DISPLAY; ignore the argument */
        } else {
            if (!quiet)
                fprintf(stderr, "xrdb: unknown option %s\n", a);
            usage();
            return 1;
        }
    }

    dpy = XOpenDisplay(NULL);
    if (!dpy) {
        if (!quiet)
            fprintf(stderr, "xrdb: cannot open display\n");
        return 1;
    }
    root = DefaultRootWindow(dpy);
    rm = XInternAtom(dpy, "RESOURCE_MANAGER", False);

    if (query) {
        unsigned char *val = NULL;
        Atom type;
        int fmt;
        unsigned long nit, after;
        if (XGetWindowProperty(dpy, root, rm, 0, 1000000, False, XA_STRING,
                               &type, &fmt, &nit, &after, &val) == Success &&
            val) {
            fwrite(val, 1, nit, stdout);
            XFree(val);
        }
        XCloseDisplay(dpy);
        return 0;
    }

    /* Build the input. */
    for (i = 0; i < nfiles; i++) {
        FILE *f = fopen(files[i], "r");
        char buf[4096];
        if (!f)
            continue;
        while (fgets(buf, sizeof buf, f)) {
            size_t l = strlen(buf);
            if (len + l + 2 > cap) {
                cap = (len + l + 2) * 2;
                text = realloc(text, cap);
            }
            memcpy(text + len, buf, l);
            len += l;
            text[len] = 0;
        }
        fclose(f);
    }
    if (nfiles == 0) {
        char buf[4096];
        while (fgets(buf, sizeof buf, stdin)) {
            size_t l = strlen(buf);
            if (len + l + 2 > cap) {
                cap = (len + l + 2) * 2;
                text = realloc(text, cap);
            }
            memcpy(text + len, buf, l);
            len += l;
            text[len] = 0;
        }
    }

    if (!nocpp && text && text[0]) {
        char *processed = preprocess(text, cppargs, ncpp);
        if (processed) {
            free(text);
            text = processed;
        }
    }
    if (!text)
        text = strdup("");

    /* Read what is already there. */
    {
        unsigned char *val = NULL;
        Atom type;
        int fmt;
        unsigned long nit, after;
        if (XGetWindowProperty(dpy, root, rm, 0, 1000000, False, XA_STRING,
                               &type, &fmt, &nit, &after, &val) == Success &&
            val)
            existing = (char *) val;   /* freed with XFree below */
    }

    /* Both -load and -merge add to the database rather than replacing it.  A
     * replace is what -load means in a normal session, where the server owns
     * the whole database; here the property is shared: it also carries the
     * colour server's palette and is relayed to clients that merge it with the
     * file sources, so replacing it would throw both away.  Additions are the
     * safe reading, and since the relayed value is merged last, what is loaded
     * still takes effect over the file sources. */
    {
        size_t elen = strlen(text);
        size_t xlen = existing ? strlen(existing) : 0;
        (void) merge;
        char *out = malloc(xlen + elen + 2);
        if (!out) {
            XCloseDisplay(dpy);
            return 1;
        }
        if (xlen) {
            memcpy(out, existing, xlen);
            if (xlen && existing[xlen - 1] != '\n')
                out[xlen++] = '\n';
        }
        memcpy(out + xlen, text, elen);
        out[xlen + elen] = 0;
        XChangeProperty(dpy, root, rm, XA_STRING, 8, PropModeReplace,
                        (unsigned char *) out, (int) (xlen + elen));
        free(out);
    }

    if (existing)
        XFree(existing);
    free(text);
    XSync(dpy, False);
    XCloseDisplay(dpy);
    return 0;
}
