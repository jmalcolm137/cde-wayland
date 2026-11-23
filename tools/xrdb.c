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
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#define MAXFILES 32
#define MAXCPPARGS 64

static void
usage(void)
{
    fprintf(stderr, "usage: xrdb [-quiet] [-load|-merge] [-nocpp] "
                    "[-Dname[=value]] [-Uname] [-Idir] [-file file]... "
                    "[-query|-o]\n");
}

static int
append_bytes(char **buf, size_t *len, size_t *cap, const char *src, size_t n)
{
    if (*len + n + 1 > *cap) {
        size_t ncap = *cap ? *cap : 4096;
        while (*len + n + 1 > ncap)
            ncap *= 2;
        char *t = realloc(*buf, ncap);
        if (!t)
            return -1;
        *buf = t;
        *cap = ncap;
    }
    memcpy(*buf + *len, src, n);
    *len += n;
    (*buf)[*len] = 0;
    return 0;
}

static int
read_stream(FILE *f, char **buf, size_t *len, size_t *cap)
{
    char tmp[4096];
    size_t n;

    while ((n = fread(tmp, 1, sizeof tmp, f)) > 0) {
        if (append_bytes(buf, len, cap, tmp, n) < 0)
            return -1;
    }
    return ferror(f) ? -1 : 0;
}

/* Run the input through cpp without invoking a shell, returning its stdout
 * (malloc'd).  -traditional-cpp is used because CDE's resource files contain
 * quotes and backslashes that the modern preprocessor would rewrite. */
static char *
preprocess(const char *input, size_t inlen, char *const *deflist, int ndef)
{
    int to_cpp[2], from_cpp[2];
    pid_t pid;
    char *out = NULL;
    size_t outlen = 0, outcap = 0;
    size_t sent = 0;

    if (pipe(to_cpp) < 0)
        return NULL;
    if (pipe(from_cpp) < 0) {
        close(to_cpp[0]);
        close(to_cpp[1]);
        return NULL;
    }

    pid = fork();
    if (pid < 0) {
        close(to_cpp[0]); close(to_cpp[1]);
        close(from_cpp[0]); close(from_cpp[1]);
        return NULL;
    }
    if (pid == 0) {
        const char *argv[MAXCPPARGS + 5];
        int argc = 0;
        int devnull;

        dup2(to_cpp[0], STDIN_FILENO);
        dup2(from_cpp[1], STDOUT_FILENO);
        devnull = open("/dev/null", O_WRONLY);
        if (devnull >= 0) {
            dup2(devnull, STDERR_FILENO);
            close(devnull);
        }
        close(to_cpp[0]); close(to_cpp[1]);
        close(from_cpp[0]); close(from_cpp[1]);

        argv[argc++] = "cpp";
        argv[argc++] = "-traditional-cpp";
        argv[argc++] = "-P";
        for (int i = 0; i < ndef && i < MAXCPPARGS; i++)
            argv[argc++] = deflist[i];
        argv[argc++] = "-";
        argv[argc] = NULL;

        execvp("cpp", (char *const *)argv);
        _exit(127);
    }

    close(to_cpp[0]);
    close(from_cpp[1]);

    /* Avoid SIGPIPE if cpp exits early; pump stdin and stdout concurrently so
     * large inputs cannot deadlock on pipe buffers. */
    signal(SIGPIPE, SIG_IGN);
    fcntl(to_cpp[1], F_SETFL, fcntl(to_cpp[1], F_GETFL, 0) | O_NONBLOCK);
    fcntl(from_cpp[0], F_SETFL, fcntl(from_cpp[0], F_GETFL, 0) | O_NONBLOCK);

    int wfd = to_cpp[1];
    int rfd = from_cpp[0];
    int oom = 0;

    if (inlen == 0) {
        close(wfd);
        wfd = -1;
    }

    while (wfd >= 0 || rfd >= 0) {
        struct pollfd fds[2];
        nfds_t nfds = 0;
        int wi = -1, ri = -1;

        if (wfd >= 0) {
            wi = (int)nfds;
            fds[nfds].fd = wfd;
            fds[nfds].events = POLLOUT;
            fds[nfds].revents = 0;
            nfds++;
        }
        if (rfd >= 0) {
            ri = (int)nfds;
            fds[nfds].fd = rfd;
            fds[nfds].events = POLLIN;
            fds[nfds].revents = 0;
            nfds++;
        }

        if (poll(fds, nfds, -1) < 0) {
            if (errno == EINTR)
                continue;
            break;
        }

        if (wi >= 0 && (fds[wi].revents & (POLLOUT | POLLERR | POLLHUP))) {
            ssize_t n = write(wfd, input + sent, inlen - sent);
            if (n > 0) {
                sent += (size_t)n;
                if (sent >= inlen) {
                    close(wfd);
                    wfd = -1;
                }
            } else if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK &&
                       errno != EINTR) {
                close(wfd);
                wfd = -1;
            }
        }

        if (ri >= 0 && (fds[ri].revents & (POLLIN | POLLHUP | POLLERR))) {
            char buf[4096];
            ssize_t n = read(rfd, buf, sizeof buf);
            if (n > 0) {
                if (!oom && append_bytes(&out, &outlen, &outcap, buf, (size_t)n) < 0)
                    oom = 1;
            } else if (n == 0 || (errno != EAGAIN && errno != EWOULDBLOCK &&
                                  errno != EINTR)) {
                close(rfd);
                rfd = -1;
            }
        }
    }

    if (wfd >= 0) close(wfd);
    if (rfd >= 0) close(rfd);

    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
        ;
    if (oom || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        free(out);
        return NULL;
    }
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
        if (!f)
            continue;
        if (read_stream(f, &text, &len, &cap) < 0) {
            fclose(f);
            free(text);
            XCloseDisplay(dpy);
            return 1;
        }
        fclose(f);
    }
    if (nfiles == 0) {
        if (read_stream(stdin, &text, &len, &cap) < 0) {
            free(text);
            XCloseDisplay(dpy);
            return 1;
        }
    }

    if (!nocpp && text && len > 0) {
        char *processed = preprocess(text, len, cppargs, ncpp);
        if (processed) {
            free(text);
            text = processed;
        }
    }
    if (!text) {
        text = strdup("");
        if (!text) {
            XCloseDisplay(dpy);
            return 1;
        }
    }

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
