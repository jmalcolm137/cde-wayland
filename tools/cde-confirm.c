/* cde-confirm.c — a Motif question dialog for the cde-wayland shell helpers.
 *
 * Under the shim every client is its own X server, so dtsession cannot post the
 * session manager's "are you sure?" dialog; the Front Panel's Exit control runs
 * cde-logout in this process tree instead, and cde-logout uses this small client
 * for the confirmation.  Whether it is shown is the Style Manager's Startup
 * module setting.
 *
 *     cde-confirm TITLE MESSAGE
 *
 * Exit status is 0 when confirmed (OK) and 1 otherwise.
 */
#include <X11/Intrinsic.h>
#include <Xm/Xm.h>
#include <Xm/MessageB.h>
#include <stdio.h>
#include <stdlib.h>

static XtAppContext app;
static int done;
static int confirmed;

static void
onOk(Widget w, XtPointer cd, XtPointer cbd)
{
    (void) w; (void) cd; (void) cbd;
    confirmed = 1;
    done = 1;
}

static void
onCancel(Widget w, XtPointer cd, XtPointer cbd)
{
    (void) w; (void) cd; (void) cbd;
    done = 1;
}

int
main(int argc, char **argv)
{
    Widget toplevel, dialog;
    XmString title, message, ok, cancel;

    toplevel = XtAppInitialize(&app, "CdeConfirm", NULL, 0, &argc, argv,
                               NULL, NULL, 0);
    /* Xt consumes its own options; argv then holds TITLE MESSAGE. */
    if (argc < 3) {
        fprintf(stderr, "usage: cde-confirm TITLE MESSAGE\n");
        return 2;
    }

    title   = XmStringCreateLocalized(argv[1]);
    message = XmStringCreateLocalized(argv[2]);
    ok      = XmStringCreateLocalized("OK");
    cancel  = XmStringCreateLocalized("Cancel");

    dialog = XmCreateQuestionDialog(toplevel, "confirm", NULL, 0);
    XtVaSetValues(dialog,
                  XmNdialogTitle, title,
                  XmNmessageString, message,
                  XmNokLabelString, ok,
                  XmNcancelLabelString, cancel,
                  XmNdialogStyle, XmDIALOG_FULL_APPLICATION_MODAL,
                  NULL);
    XtUnmanageChild(XmMessageBoxGetChild(dialog, XmDIALOG_HELP_BUTTON));
    XtAddCallback(dialog, XmNokCallback, onOk, NULL);
    XtAddCallback(dialog, XmNcancelCallback, onCancel, NULL);

    XtManageChild(dialog);
    while (!done)
        XtAppProcessEvent(app, XtIMAll);

    XmStringFree(title);
    XmStringFree(message);
    XmStringFree(ok);
    XmStringFree(cancel);
    return confirmed ? 0 : 1;
}
