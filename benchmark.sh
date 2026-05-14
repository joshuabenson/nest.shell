#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  benchmark.sh  -  nest.shell benchmark (apache bench)
#  Usage: PORT=8090 ./benchmark.sh
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

PORT="${PORT:-8090}"
BASE="http://localhost:$PORT"
BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'

command -v ab >/dev/null || { echo "Need: sudo apt install apache2-utils"; exit 1; }

warmup() { curl -s -o /dev/null "$BASE$1" 2>/dev/null || true; }

bench() {
    local label="$1" path="$2" n="${3:-1000}" c="${4:-1}" method="${5:-GET}" postfile="${6:-}"

    echo -ne "  ${CYAN}%-30s${RESET} " "$label"

    local ab_out
    if [ "$method" = "POST" ] && [ -n "$postfile" ]; then
        ab_out=$(ab -q -n "$n" -c "$c" -T 'application/json' -p "$postfile" "$BASE$path" 2>/dev/null)
    else
        ab_out=$(ab -q -n "$n" -c "$c" "$BASE$path" 2>/dev/null)
    fi

    local rps mean p50 p95 p99 fails ok_req
    rps=$(echo  "$ab_out" | grep "Requests per second"       | awk '{print $4}')
    mean=$(echo "$ab_out" | grep "Time per request.*mean"    | head -1 | awk '{print $4}')
    p50=$(echo  "$ab_out" | grep "^ *50%"                    | awk '{print $2}')
    p95=$(echo  "$ab_out" | grep "^ *95%"                    | awk '{print $2}')
    p99=$(echo  "$ab_out" | grep "^ *99%"                    | awk '{print $2}')
    ok_req=$(echo "$ab_out" | grep "Complete requests"       | awk '{print $3}')
    fails=$(echo "$ab_out" | grep "Failed requests"          | awk '{print $3}')

    # Color-code throughput
    local color="$GREEN"
    [ "$(echo "$rps < 20" | bc -l 2>/dev/null)" = "1" ] && color="$YELLOW"
    [ "$(echo "$rps < 10" | bc -l 2>/dev/null)" = "1" ] && color="$RED"

    printf "${color}%8s req/s${RESET}  avg %6sms  p50 %5sms  p95 %5sms  p99 %5sms  (${ok_req:-?} ok" "$rps" "$mean" "$p50" "$p95" "$p99"
    [ "${fails:-0}" != "0" ] && echo -ne ", ${RED}$fails fail${RESET}"
    echo ")"
}

echo -e "${BOLD}╔══════════════════════════════════════════════════════╗"
echo -e "║  nest.shell Benchmark  (apache bench)               ║"
echo -e "╠══════════════════════════════════════════════════════╣"
echo -e "║  Rate limiting disabled for accurate measurement    ║"
echo -e "╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${YELLOW}Warming up...${RESET}"
warmup "/home"
warmup "/api/todo/list"
warmup "/home/style.css"
warmup "/todo"
echo ""

# ─── 1. Endpoint-type throughput ───────────────────────────
echo -e "${BOLD}── 1. Throughput by endpoint (1000 req, 1 conn) ──${RESET}"
bench "Static CSS file         " "/home/style.css"           1000 1
bench "Simple page /home       " "/home"                     1000 1
bench "Page+DB /todo           " "/todo"                     1000 1
bench "API: list todos (GET)   " "/api/todo/list"            1000 1
bench "API: list guestbook     " "/api/guestbook/list"       1000 1

# POST needs a temp file for ab
echo -n '{"task":"benchmark-test"}' > /tmp/nest-bench-post.json
bench "API: add todo (POST+DB) " "/api/todo/add"              500 1  POST /tmp/nest-bench-post.json

echo ""
# ─── 2. Concurrency scaling ────────────────────────────────
echo -e "${BOLD}── 2. Concurrency scaling (/api/todo/list, 2000 req) ──${RESET}"
bench "  C=1                    " "/api/todo/list"            2000 1
bench "  C=5                    " "/api/todo/list"            2000 5
bench "  C=10                   " "/api/todo/list"            2000 10
bench "  C=25                   " "/api/todo/list"            2000 25
bench "  C=50                   " "/api/todo/list"            2000 50

echo ""
# ─── 3. Static file at load ────────────────────────────────
echo -e "${BOLD}── 3. Static file stress (CSS) ──${RESET}"
bench "  5k req, C=10           " "/home/style.css"           5000 10
bench "  5k req, C=50           " "/home/style.css"           5000 50

echo ""
# ─── 4. Cost comparison ────────────────────────────────────
echo -e "${BOLD}── 4. Request cost breakdown ──${RESET}"
echo -e "  ${CYAN}Endpoint          Cost per request (avg ms)${RESET}"
for path in "/home/style.css" "/home" "/todo" "/api/todo/list" "/api/guestbook/list"; do
    ab_out=$(ab -q -n 100 -c 1 "$BASE$path" 2>/dev/null)
    avg=$(echo "$ab_out" | grep "Time per request.*mean" | head -1 | awk '{print $4}')
    label=${path#/}
    printf "  %-25s %6s ms\n" "$label" "$avg"
done
# POST separately
ab_out=$(ab -q -n 50 -c 1 -T 'application/json' -p /tmp/nest-bench-post.json "$BASE/api/todo/add" 2>/dev/null)
avg=$(echo "$ab_out" | grep "Time per request.*mean" | head -1 | awk '{print $4}')
printf "  %-25s %6s ms\n" "/api/todo/add (POST)" "$avg"

rm -f /tmp/nest-bench-post.json

echo ""
echo -e "${YELLOW}── Notes ──${RESET}"
echo "  • socat fork()+exec() bash ≈ 3-6ms per request overhead"
echo "  • SQLite in WAL mode would improve concurrent writes"
echo "  • nginx static: ~50k req/s | node express: ~5k req/s"
echo "  • This is a BASH web framework. Perspective matters. 🐚"
echo ""
echo "  Run with:  MAX_REQUESTS_PER_MIN=999999 PORT=8080 ./benchmark.sh"
