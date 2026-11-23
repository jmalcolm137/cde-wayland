/* cde-wsm.c — drive the CDE Workspace Manager from the shell / a menu.
 *
 * A small client for the DtWsm API, used by CoW's root and window menus (see
 * config/cow.conf) to run the CDE Workspace Manager's own functions:
 *
 *     cde-wsm list            list workspaces, current marked with '*'
 *     cde-wsm switch N        switch to workspace index N
 *     cde-wsm next            next workspace
 *     cde-wsm prev            previous workspace
 *     cde-wsm add TITLE       add a workspace
 *     cde-wsm delete N        delete workspace index N
 *     cde-wsm rename N TITLE  set workspace N's title
 *
 * Because it goes through the DtWsm API, dtwm performs the change itself (and
 * the dtwm->CoW bridge records it), so the Front Panel stays in step rather
 * than CoW moving on its own.
 */
#include <X11/Intrinsic.h>
#include <Dt/Wsm.h>
#include <Tt/tt_c.h>
#include <errno.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static long long now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL;
}

/* ToolTalk requests are asynchronous.  Wait on the X and ToolTalk file
 * descriptors for the reply rather than sleeping a fixed 600ms, exiting once
 * the exchange settles or the 600ms cap expires. */
static void settle(XtAppContext app, Display *d)
{
    int xfd = ConnectionNumber(d);
    int ttfd = tt_fd();
    long long deadline = now_ms() + 600;
    int got_reply = 0;

    for (;;) {
        while (XtAppPending(app)) {
            XtAppProcessEvent(app, XtIMAll);
            got_reply = 1;
        }
        XFlush(d);

        long long rem = deadline - now_ms();
        if (rem <= 0)
            break;
        int wait_ms = got_reply ? 30 : 80;
        if (wait_ms > rem)
            wait_ms = (int)rem;

        struct pollfd fds[2];
        nfds_t nfds = 0;
        if (xfd >= 0) {
            fds[nfds].fd = xfd;
            fds[nfds].events = POLLIN;
            fds[nfds].revents = 0;
            nfds++;
        }
        if (ttfd >= 0 && ttfd != xfd) {
            fds[nfds].fd = ttfd;
            fds[nfds].events = POLLIN;
            fds[nfds].revents = 0;
            nfds++;
        }
        int r = poll(fds, nfds, wait_ms);
        if (r < 0) {
            if (errno == EINTR)
                continue;
            break;
        }
        if (r == 0)
            break;
        /* Drain any ToolTalk messages ready on ttfd. */
        if (ttfd >= 0) {
            Tt_message msg = tt_message_receive();
            if (msg && tt_ptr_error(msg) == TT_OK) {
                tt_message_destroy(msg);
                got_reply = 1;
            }
        }
    }
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr,
                "usage: cde-wsm list|switch N|next|prev|add TITLE|delete N|"
                "rename N TITLE\n");
        return 2;
    }

    XtAppContext app;
    Widget top = XtAppInitialize(&app, "CDEWsm", NULL, 0, &argc, argv,
                                 NULL, NULL, 0);
    /* DtSvc's WSM calls build ToolTalk messages, which need a default procid. */
    {
        char *procid = tt_open();
        if (tt_ptr_error(procid) != TT_OK) {
            fprintf(stderr, "cde-wsm: no ToolTalk session: %s\n",
                    tt_status_message(tt_ptr_error(procid)));
            return 1;
        }
    }

    Display *d = XtDisplay(top);
    Window root = DefaultRootWindow(d);
    Atom *list = NULL;
    int n = 0;
    if (DtWsmGetWorkspaceList(d, root, &list, &n) != 0 || n <= 0) {
        fprintf(stderr, "cde-wsm: no workspaces (is the Workspace Manager running?)\n");
        return 1;
    }

    Atom cur = 0;
    (void) DtWsmGetCurrentWorkspace(d, root, &cur);
    int idx = 0;
    for (int i = 0; i < n; i++)
        if (list[i] == cur) idx = i;

    const char *cmd = argv[1];
    int rc = 0;
    int switching = 1;
    int failed = 0;
    if (strcmp(cmd, "list") == 0) {
        for (int i = 0; i < n; i++) {
            char *nm = XGetAtomName(d, list[i]);
            printf("%d %s%s\n", i, nm ? nm : "?", list[i] == cur ? " *" : "");
            if (nm) XFree(nm);
        }
        return 0;
    } else if (strcmp(cmd, "add") == 0 && argc > 2) {
        /* The Add/Delete/Title wrappers return Success (0) on success. */
        rc = DtWsmAddWorkspace(top, argv[2]);
        failed = (rc != 0);
        switching = 0;
    } else if (strcmp(cmd, "delete") == 0 && argc > 2) {
        idx = atoi(argv[2]);
        if (idx < 0 || idx >= n) {
            fprintf(stderr, "cde-wsm: no workspace %d\n", idx);
            return 2;
        }
        rc = DtWsmDeleteWorkspace(top, list[idx]);
        failed = (rc != 0);
        switching = 0;
    } else if (strcmp(cmd, "rename") == 0 && argc > 3) {
        idx = atoi(argv[2]);
        if (idx < 0 || idx >= n) {
            fprintf(stderr, "cde-wsm: no workspace %d\n", idx);
            return 2;
        }
        rc = DtWsmSetWorkspaceTitle(top, list[idx], argv[3]);
        failed = (rc != 0);
        switching = 0;
    } else if (strcmp(cmd, "switch") == 0 && argc > 2) {
        idx = atoi(argv[2]);
    } else if (strcmp(cmd, "next") == 0) {
        idx = (idx + 1) % n;
    } else if (strcmp(cmd, "prev") == 0) {
        idx = (idx - 1 + n) % n;
    } else {
        fprintf(stderr, "cde-wsm: unknown command '%s'\n", cmd);
        return 2;
    }

    if (switching) {
        if (idx < 0 || idx >= n) idx = 0;
        rc = DtWsmSetCurrentWorkspace(top, list[idx]);
        /* DtWsmSetCurrentWorkspace returns dtmsg_SUCCESS (1, not Success) on
         * success -- a preserved CDE 1.0 quirk -- and dtmsg_FAIL (-1) on
         * failure. */
        failed = (rc < 0);
    }
    if (failed)
        fprintf(stderr, "cde-wsm: %s failed (%d)\n", cmd, rc);
    settle(app, d);
    return failed;
}
