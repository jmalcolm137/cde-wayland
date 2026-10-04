/* cde-wsm.c — drive the CDE Workspace Manager from the shell / a menu.
 *
 * A small client for the DtWsm API, used by CoW's root menu (see
 * config/cow.conf) to run the CDE Workspace Manager's own functions:
 *
 *     cde-wsm list            list workspaces, current marked with '*'
 *     cde-wsm switch N        switch to workspace index N
 *     cde-wsm next            next workspace
 *     cde-wsm prev            previous workspace
 *
 * Because it goes through DtWsmSetCurrentWorkspace(), dtwm performs the change
 * itself (and the dtwm->CoW bridge records it), so the Front Panel stays in
 * step rather than CoW moving on its own.
 */
#include <X11/Intrinsic.h>
#include <Dt/Wsm.h>
#include <Tt/tt_c.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: cde-wsm list|switch N|next|prev\n");
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
    if (strcmp(cmd, "list") == 0) {
        for (int i = 0; i < n; i++) {
            char *nm = XGetAtomName(d, list[i]);
            printf("%d %s%s\n", i, nm ? nm : "?", list[i] == cur ? " *" : "");
            if (nm) XFree(nm);
        }
        return 0;
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

    if (idx < 0 || idx >= n) idx = 0;
    (void) DtWsmSetCurrentWorkspace(top, list[idx]);
    XSync(d, False);
    return 0;
}
