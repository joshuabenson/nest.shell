/* ═══════════════════════════════════════════════════════════
 *  nestsrv.c — "assembly-level" TCP shim for nest.shell
 *  Replaces socat. 30 lines of C. Compiles to ~16KB.
 *  
 *  cc -O3 -s -o nestsrv nestsrv.c
 *  PORT=8080 ./nest.sh --srv ./nestsrv
 *
 *  Still forks per request, but avoids socat's 400KB binary.
 *  For REAL speed: use the pre-fork model (see nest-fork.sh).
 * ═══════════════════════════════════════════════════════════ */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <signal.h>

#define BACKLOG 128

static void handle(int fd, char *script) {
    dup2(fd, 0); dup2(fd, 1); close(fd);
    execlp("bash", "bash", script, "handle_connection", NULL);
    perror("execlp"); _exit(1);
}

int main(int argc, char **argv) {
    int port = 8080;
    char *script = "./nest.sh";
    if (argc > 1) port = atoi(argv[1]);
    if (argc > 2) script = argv[2];

    signal(SIGCHLD, SIG_IGN);  // reap children

    int s = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr = {.sin_family = AF_INET,
                               .sin_port = htons(port),
                               .sin_addr.s_addr = INADDR_ANY};
    bind(s, (struct sockaddr *)&addr, sizeof(addr));
    listen(s, BACKLOG);

    fprintf(stderr, "nestsrv: listening on :%d (script: %s)\n", port, script);

    for (;;) {
        int c = accept(s, NULL, NULL);
        if (c < 0) continue;
        if (fork() == 0) { close(s); handle(c, script); }
        close(c);
    }
}
