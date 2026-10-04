/*
 * tt-portmapper.c — a minimal rpcbind/portmap (PMAP v2) server.
 *
 * CDE's Front Panel launches applications through ToolTalk (`dtaction` ->
 * `tt_open` -> `ttsession`).  `ttsession` cannot initialise without a
 * portmapper to register its RPC programme with, and on a modern desktop that
 * means `rpcbind`, which binds the privileged port 111 and therefore needs
 * root.
 *
 * This is just enough of the portmapper protocol for ToolTalk: it implements
 * PMAP v2 SET/UNSET/GETPORT/DUMP over IPv4 and IPv6, TCP and UDP, on port 111.
 * Run it inside an unprivileged user+network namespace (`unshare --user
 * --map-root-user --net`) where binding 111 is permitted, and real `ttsession`
 * comes up without root.  See scripts/run-session.sh.
 *
 * It is not a general-purpose portmapper: there is no authentication, no
 * callit, and the mapping table is a small fixed array.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <stddef.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <stdint.h>
#include <rpc/rpc.h>
#include <rpc/pmap_prot.h>
#include <rpc/rpcb_prot.h>

#define MAXMAP 256

static struct pmap maps[MAXMAP];
static int nmaps;

static void store_map(const struct pmap *m)
{
    for (int i = 0; i < nmaps; i++) {
        if (maps[i].pm_prog == m->pm_prog && maps[i].pm_vers == m->pm_vers &&
            maps[i].pm_prot == m->pm_prot) {
            maps[i].pm_port = m->pm_port;
            return;
        }
    }
    if (nmaps < MAXMAP)
        maps[nmaps++] = *m;
}

static void unstore_map(const struct pmap *m)
{
    for (int i = 0; i < nmaps; i++) {
        if (maps[i].pm_prog == m->pm_prog && maps[i].pm_vers == m->pm_vers &&
            maps[i].pm_prot == m->pm_prot) {
            maps[i] = maps[--nmaps];
            return;
        }
    }
}

static unsigned long find_port(const struct pmap *m)
{
    for (int i = 0; i < nmaps; i++)
        if (maps[i].pm_prog == m->pm_prog && maps[i].pm_vers == m->pm_vers &&
            maps[i].pm_prot == m->pm_prot)
            return maps[i].pm_port;
    return 0;
}

static void pmap_dispatch(struct svc_req *rqstp, SVCXPRT *transp)
{
    struct pmap m;
    bool_t ok = TRUE;
    unsigned long port;

    switch (rqstp->rq_proc) {
    case PMAPPROC_NULL:
        svc_sendreply(transp, (xdrproc_t)xdr_void, NULL);
        return;
    case PMAPPROC_SET:
        if (!svc_getargs(transp, (xdrproc_t)xdr_pmap, (char *)&m)) {
            fprintf(stderr, "tt-portmapper: SET decode failed\n");
            svcerr_decode(transp);
            return;
        }
        fprintf(stderr, "tt-portmapper: SET prog=%lu vers=%lu prot=%lu port=%lu\n",
                m.pm_prog, m.pm_vers, m.pm_prot, m.pm_port);
        store_map(&m);
        svc_sendreply(transp, (xdrproc_t)xdr_bool, (char *)&ok);
        return;
    case PMAPPROC_UNSET:
        if (!svc_getargs(transp, (xdrproc_t)xdr_pmap, (char *)&m)) {
            svcerr_decode(transp);
            return;
        }
        unstore_map(&m);
        svc_sendreply(transp, (xdrproc_t)xdr_bool, (char *)&ok);
        return;
    case PMAPPROC_GETPORT:
        if (!svc_getargs(transp, (xdrproc_t)xdr_pmap, (char *)&m)) {
            svcerr_decode(transp);
            return;
        }
        port = find_port(&m);
        svc_sendreply(transp, (xdrproc_t)xdr_u_long, (char *)&port);
        return;
    case PMAPPROC_DUMP: {
        struct pmaplist *list = NULL, *node;
        for (int i = nmaps - 1; i >= 0; i--) {
            node = malloc(sizeof *node);
            if (!node) break;
            node->pml_map = maps[i];
            node->pml_next = list;
            list = node;
        }
        svc_sendreply(transp, (xdrproc_t)xdr_pmaplist, (char *)&list);
        while (list) {
            node = list->pml_next;
            free(list);
            list = node;
        }
        return;
    }
    default:
        svcerr_noproc(transp);
        return;
    }
}

/* ------------------------------------------------------------------ rpcbind
 * v3/v4 (RPCB).  Modern libtirpc registers services with rpcbind v4, not the
 * old PMAP v2 SET, so ttsession needs this too.  Only SET/UNSET/GETADDR/DUMP
 * are implemented; ToolTalk does not use the rest.
 */
struct rpcbmap {
    unsigned long prog, vers;
    char *netid, *addr;
};
static struct rpcbmap rbmap[MAXMAP];
static int nrb;

static void store_rpcb(const struct rpcb *m)
{
    for (int i = 0; i < nrb; i++) {
        if (rbmap[i].prog == m->r_prog && rbmap[i].vers == m->r_vers &&
            strcmp(rbmap[i].netid, m->r_netid) == 0) {
            free(rbmap[i].addr);
            rbmap[i].addr = strdup(m->r_addr ? m->r_addr : "");
            return;
        }
    }
    if (nrb < MAXMAP) {
        rbmap[nrb].prog = m->r_prog;
        rbmap[nrb].vers = m->r_vers;
        rbmap[nrb].netid = strdup(m->r_netid ? m->r_netid : "");
        rbmap[nrb].addr = strdup(m->r_addr ? m->r_addr : "");
        nrb++;
    }
}

static void unstore_rpcb(const struct rpcb *m)
{
    for (int i = 0; i < nrb; i++) {
        if (rbmap[i].prog == m->r_prog && rbmap[i].vers == m->r_vers &&
            strcmp(rbmap[i].netid, m->r_netid) == 0) {
            free(rbmap[i].netid);
            free(rbmap[i].addr);
            rbmap[i] = rbmap[--nrb];
            return;
        }
    }
}

static const char *find_rpcb_vers(unsigned long prog, unsigned long vers,
                                  int exact_vers, const char *netid)
{
    const char *any = NULL;
    int want_any = (netid == NULL || *netid == '\0');
    for (int i = 0; i < nrb; i++) {
        if (rbmap[i].prog != prog)
            continue;
        if (exact_vers && rbmap[i].vers != vers)
            continue;
        if (!want_any) {
            if (strcmp(rbmap[i].netid, netid) == 0)
                return rbmap[i].addr;
            continue;
        }
        /* Empty netid means "any transport"; prefer tcp. */
        if (strcmp(rbmap[i].netid, "tcp") == 0)
            return rbmap[i].addr;
        if (!any)
            any = rbmap[i].addr;
    }
    return want_any ? any : NULL;
}

static void rpcb_dispatch(struct svc_req *rqstp, SVCXPRT *transp)
{
    struct rpcb m;
    bool_t ok = TRUE;

    switch (rqstp->rq_proc) {
    case 0: /* RPCB v3/v4 NULL, same number as PMAPPROC_NULL */
        svc_sendreply(transp, (xdrproc_t)xdr_void, NULL);
        return;
    case RPCBPROC_SET:
        memset(&m, 0, sizeof m);
        if (!svc_getargs(transp, (xdrproc_t)xdr_rpcb, (char *)&m)) {
            svcerr_decode(transp);
            return;
        }
        fprintf(stderr, "tt-portmapper: RPCB SET prog=%lu vers=%lu netid=%s addr=%s\n",
                (unsigned long)m.r_prog, (unsigned long)m.r_vers,
                m.r_netid ? m.r_netid : "", m.r_addr ? m.r_addr : "");
        store_rpcb(&m);
        svc_sendreply(transp, (xdrproc_t)xdr_bool, (char *)&ok);
        return;
    case RPCBPROC_UNSET:
        memset(&m, 0, sizeof m);
        if (!svc_getargs(transp, (xdrproc_t)xdr_rpcb, (char *)&m)) {
            svcerr_decode(transp);
            return;
        }
        unstore_rpcb(&m);
        svc_sendreply(transp, (xdrproc_t)xdr_bool, (char *)&ok);
        return;
    case RPCBPROC_GETADDR:
    case RPCBPROC_GETVERSADDR: {
        memset(&m, 0, sizeof m);
        if (!svc_getargs(transp, (xdrproc_t)xdr_rpcb, (char *)&m)) {
            svcerr_decode(transp);
            return;
        }
        /* GETADDR matches any version of the program; GETVERSADDR requires
         * the exact one. */
        int exact = (rqstp->rq_proc == RPCBPROC_GETVERSADDR);
        const char *a = find_rpcb_vers(m.r_prog, m.r_vers, exact, m.r_netid);
        char *res = NULL;
        if (a) {
            /* ttsession binds INADDR_ANY, so it registers "0.0.0.0.<port>".
             * Clients cannot connect to 0.0.0.0; hand them loopback. */
            if (strncmp(a, "0.0.0.0.", 8) == 0) {
                res = malloc(strlen(a) + 8);
                if (res)
                    sprintf(res, "127.0.0.1.%s", a + 8);
            } else {
                res = strdup(a);
            }
        }
        svc_sendreply(transp, (xdrproc_t)xdr_wrapstring, (char *)&res);
        free(res);
        return;
    }
    case RPCBPROC_DUMP: {
        rpcblist_ptr list = NULL;
        for (int i = nrb - 1; i >= 0; i--) {
            rpcblist_ptr node = malloc(sizeof *node);
            if (!node) break;
            memset(node, 0, sizeof *node);
            node->rpcb_map.r_prog = rbmap[i].prog;
            node->rpcb_map.r_vers = rbmap[i].vers;
            node->rpcb_map.r_netid = rbmap[i].netid;
            node->rpcb_map.r_addr = rbmap[i].addr;
            node->rpcb_map.r_owner = "";
            node->rpcb_next = list;
            list = node;
        }
        svc_sendreply(transp, (xdrproc_t)xdr_rpcblist_ptr, (char *)&list);
        while (list) {
            rpcblist_ptr next = list->rpcb_next;
            free(list);
            list = next;
        }
        return;
    }
    default:
        svcerr_noproc(transp);
        return;
    }
}

static int bind_inet(int type, int family, int port)
{
    int fd = socket(family, type, 0);
    if (fd < 0)
        return -1;
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    if (family == AF_INET6)
        setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &one, sizeof one);

    if (family == AF_INET) {
        struct sockaddr_in sa;
        memset(&sa, 0, sizeof sa);
        sa.sin_family = AF_INET;
        sa.sin_port = htons((uint16_t)port);
        sa.sin_addr.s_addr = htonl(INADDR_ANY);
        if (bind(fd, (struct sockaddr *)&sa, sizeof sa) < 0) {
            close(fd);
            return -1;
        }
    } else {
        struct sockaddr_in6 sa;
        memset(&sa, 0, sizeof sa);
        sa.sin6_family = AF_INET6;
        sa.sin6_port = htons((uint16_t)port);
        sa.sin6_addr = in6addr_any;
        if (bind(fd, (struct sockaddr *)&sa, sizeof sa) < 0) {
            close(fd);
            return -1;
        }
    }
    if (type == SOCK_STREAM && listen(fd, 16) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static void serve(int fd, int type, int family, int port)
{
    if (fd < 0)
        return;
    SVCXPRT *x = (type == SOCK_STREAM) ? svc_vc_create(fd, 4096, 4096)
                                       : svc_dg_create(fd, 4096, 4096);
    if (!x) {
        fprintf(stderr, "tt-portmapper: svc_create failed for %s/%s\n",
                family == AF_INET ? "inet" : "inet6",
                type == SOCK_STREAM ? "tcp" : "udp");
        close(fd);
        return;
    }
    /* protocol 0: do not register with a portmapper (we are it).  Offer the
     * old PMAP v2 and the modern rpcbind v3/v4, since libtirpc uses the
     * latter for svc_register(). */
    if (!svc_register(x, PMAPPROG, PMAPVERS, pmap_dispatch, 0))
        fprintf(stderr, "tt-portmapper: svc_register (pmap) failed\n");
    if (!svc_register(x, RPCBPROG, RPCBVERS, rpcb_dispatch, 0))
        fprintf(stderr, "tt-portmapper: svc_register (rpcb v3) failed\n");
    if (!svc_register(x, RPCBPROG, RPCBVERS4, rpcb_dispatch, 0))
        fprintf(stderr, "tt-portmapper: svc_register (rpcb v4) failed\n");
    (void)port;
}

/* Modern libtirpc looks for the portmapper on the abstract Unix socket
 * "@/run/rpcbind.sock" before the TCP/UDP port.  Listening there needs no
 * privileges at all, so ttsession can register without root and without a
 * network namespace (which would otherwise break name resolution). */
static void serve_unix_abstract(void)
{
    static const char name[] = "/run/rpcbind.sock";
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0)
        return;
    struct sockaddr_un sa;
    memset(&sa, 0, sizeof sa);
    sa.sun_family = AF_UNIX;
    sa.sun_path[0] = '\0';
    memcpy(sa.sun_path + 1, name, sizeof name - 1);
    socklen_t len = (socklen_t)(offsetof(struct sockaddr_un, sun_path) +
                                1 + sizeof name - 1);
    if (bind(fd, (struct sockaddr *)&sa, len) < 0 || listen(fd, 16) < 0) {
        close(fd);
        return;
    }
    SVCXPRT *x = svc_vc_create(fd, 4096, 4096);
    if (!x) {
        close(fd);
        return;
    }
    svc_register(x, PMAPPROG, PMAPVERS, pmap_dispatch, 0);
    svc_register(x, RPCBPROG, RPCBVERS, rpcb_dispatch, 0);
    svc_register(x, RPCBPROG, RPCBVERS4, rpcb_dispatch, 0);
    fprintf(stderr, "tt-portmapper: listening on @/run/rpcbind.sock\n");
}

int main(int argc, char **argv)
{
    int port = 111;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-p") && i + 1 < argc)
            port = atoi(argv[++i]);
    }

    serve_unix_abstract();
    serve(bind_inet(SOCK_DGRAM, AF_INET, port), SOCK_DGRAM, AF_INET, port);
    serve(bind_inet(SOCK_STREAM, AF_INET, port), SOCK_STREAM, AF_INET, port);
    serve(bind_inet(SOCK_DGRAM, AF_INET6, port), SOCK_DGRAM, AF_INET6, port);
    serve(bind_inet(SOCK_STREAM, AF_INET6, port), SOCK_STREAM, AF_INET6, port);

    fprintf(stderr, "tt-portmapper: listening on port %d\n", port);
    svc_run();
    return 0;
}
