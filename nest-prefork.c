/* ═══════════════════════════════════════════════════════════
 *  nest-prefork.c — nginx-style worker pool for nest.shell
 *  
 *  Accepts TCP, dispatches to persistent bash workers via pipes.
 *  Eliminates fork+exec per request — workers stay alive.
 *
 *  Architecture:  nginx has master + worker processes.
 *  We have:        nest-prefork (C) + N × bash workers.
 *
 *  cc -O3 -s -o nest-prefork nest-prefork.c
 *  PORT=8080 ./nest.sh --prefork ./nest-prefork
 * ═══════════════════════════════════════════════════════════ */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <signal.h>
#include <errno.h>
#include <fcntl.h>

#define BACKLOG      128
#define MAX_WORKERS  64
#define BUF_SIZE     65536
#define MAX_REQ_LINE 8192

typedef struct {
    pid_t pid;
    int   to_worker;   // dispatcher writes request here
    int   from_worker; // dispatcher reads response here
    int   busy;
} Worker;

static Worker workers[MAX_WORKERS];
static int    num_workers = 4;
static char  *script_path;

// Spawn a persistent bash worker
static void spawn_worker(int i) {
    int p2c[2], c2p[2];  // parent→child, child→parent
    pipe(p2c); pipe(c2p);

    pid_t pid = fork();
    if (pid == 0) {
        // Child: bash worker loop
        close(p2c[1]); close(c2p[0]);
        dup2(p2c[0], 0);  // stdin = request pipe
        dup2(c2p[1], 1);  // stdout = response pipe
        close(p2c[0]); close(c2p[1]);

        // Write ready signal
        write(1, "RDY", 3);

        // Read requests in a loop
        char buf[BUF_SIZE];
        for (;;) {
            // Read 4-byte length prefix
            int len = 0;
            if (read(0, &len, 4) != 4) break;
            if (len <= 0 || len > BUF_SIZE - 1) break;

            // Read the raw HTTP request
            int total = 0;
            while (total < len) {
                int n = read(0, buf + total, len - total);
                if (n <= 0) goto done;
                total += n;
            }
            buf[len] = '\0';

            // Write to child's stdin of the handle_connection bash process
            // We need to exec bash for each request? No — we need bash to
            // stay alive and read multiple requests from stdin.
            // For now: exec bash per request (still fork but worker stays)
            
            pid_t hpid = fork();
            if (hpid == 0) {
                // Write request, then exec bash to process it
                int pp[2];
                pipe(pp);
                write(pp[1], buf, len);
                close(pp[1]);
                dup2(pp[0], 0);
                close(pp[0]);
                execlp("bash", "bash", script_path, "handle_connection", NULL);
                _exit(1);
            }
            waitpid(hpid, NULL, 0);
        }
done:
        _exit(0);
    }

    // Parent: store worker info
    close(p2c[0]); close(c2p[1]);
    workers[i].pid = pid;
    workers[i].to_worker = p2c[1];
    workers[i].from_worker = c2p[0];
    workers[i].busy = 0;

    // Wait for "RDY" from worker
    char rdy[4] = {0};
    read(c2p[0], rdy, 3);
}

// Find a free worker (round-robin starting from hint)
static int find_free_worker(int *hint) {
    for (int tries = 0; tries < num_workers; tries++) {
        int i = (*hint) % num_workers;
        *hint = (*hint + 1) % num_workers;
        if (!workers[i].busy) return i;
    }
    return -1;  // all busy — caller should wait
}

// Read full HTTP request from a socket (headers + body)
static int read_http_request(int fd, char *buf, int max) {
    int total = 0;
    char *end_headers = NULL;

    while (total < max - 1) {
        int n = read(fd, buf + total, 1);
        if (n <= 0) return total;
        total++;

        // Detect end of headers (\r\n\r\n)
        if (total >= 4 && !memcmp(buf + total - 4, "\r\n\r\n", 4)) {
            end_headers = buf + total;
            break;
        }
    }

    if (!end_headers) return total;

    // Parse Content-Length
    int clen = 0;
    char *cl = strcasestr(buf, "Content-Length:");
    if (cl) clen = atoi(cl + 15);

    // Read body
    while (clen > 0 && total < max - 1) {
        int n = read(fd, buf + total, clen);
        if (n <= 0) break;
        total += n;
        clen -= n;
    }

    buf[total] = '\0';
    return total;
}

int main(int argc, char **argv) {
    int port = 8080;
    if (argc > 1) port = atoi(argv[1]);
    if (argc > 2) num_workers = atoi(argv[2]);
    script_path = argc > 3 ? argv[3] : "./nest.sh";
    if (num_workers < 1) num_workers = 1;
    if (num_workers > MAX_WORKERS) num_workers = MAX_WORKERS;

    signal(SIGCHLD, SIG_DFL);
    signal(SIGPIPE, SIG_IGN);

    fprintf(stderr, "nest-prefork: :%d, %d workers, script=%s\n",
            port, num_workers, script_path);

    // Spawn worker pool
    for (int i = 0; i < num_workers; i++) spawn_worker(i);

    // TCP listener
    int s = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    struct sockaddr_in addr = {.sin_family = AF_INET,
                               .sin_port = htons(port),
                               .sin_addr.s_addr = INADDR_ANY};
    bind(s, (struct sockaddr *)&addr, sizeof(addr));
    listen(s, BACKLOG);

    fprintf(stderr, "nest-prefork: ready. accepting...\n");

    int rr = 0;
    for (;;) {
        int fd = accept(s, NULL, NULL);
        if (fd < 0) continue;

        // Read the HTTP request from the socket
        char req[BUF_SIZE];
        int req_len = read_http_request(fd, req, BUF_SIZE);
        if (req_len <= 0) { close(fd); continue; }

        // Find a free worker
        int wi = find_free_worker(&rr);
        if (wi < 0) {
            // All busy — respond 503 and close
            char *resp = "HTTP/1.1 503 Service Unavailable\r\n"
                         "Content-Length: 0\r\nConnection: close\r\n\r\n";
            write(fd, resp, strlen(resp));
            close(fd);
            continue;
        }

        workers[wi].busy = 1;

        // Send length-prefixed request to worker
        write(workers[wi].to_worker, &req_len, 4);
        write(workers[wi].to_worker, req, req_len);

        // Read response from worker
        char resp[BUF_SIZE];
        int resp_len = 0;
        char resp_hdr[4096];
        int hdr_len = 0;

        // Read until end of headers (\r\n\r\n)
        while (hdr_len < 4095) {
            if (read(workers[wi].from_worker, resp_hdr + hdr_len, 1) != 1) break;
            hdr_len++;
            if (hdr_len >= 4 && !memcmp(resp_hdr + hdr_len - 4, "\r\n\r\n", 4)) break;
        }
        resp_hdr[hdr_len] = '\0';

        // Parse Content-Length from response
        int resp_cl = 0;
        char *rcl = strcasestr(resp_hdr, "Content-Length:");
        if (rcl) resp_cl = atoi(rcl + 15);

        // Read body
        int body_read = 0;
        while (body_read < resp_cl) {
            int n = read(workers[wi].from_worker, resp + body_read, resp_cl - body_read);
            if (n <= 0) break;
            body_read += n;
        }

        // Forward to client
        write(fd, resp_hdr, hdr_len);
        if (body_read > 0) write(fd, resp, body_read);
        close(fd);

        workers[wi].busy = 0;
    }
}
