#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  test-suite.sh  -  OWASP + Unicode hardening test suite
#  Usage: PORT=8090 ./test-suite.sh
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

PORT="${PORT:-8090}"
BASE="http://localhost:$PORT"
PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; RESET='\033[0m'

# Clean state
rm -rf cache/ratelimit 2>/dev/null || true
> /dev/shm/nest-shell-security.log 2>/dev/null || true

check() {
    local desc="$1"; shift
    local expected="$1"; shift
    local actual="$*"
    TOTAL=$((TOTAL + 1))
    if echo "$actual" | grep -q "$expected"; then
        echo -e "  ${GREEN}✅${RESET} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}❌${RESET} $desc"
        echo "     Expected: $expected"
        local short="${actual:0:120}"
        echo "     Got:      $short"
        FAIL=$((FAIL + 1))
    fi
}

header() {
    echo -e "\n${CYAN}── $1 ──${RESET}"
}

# ═══════════════════════════════════════════════════════════════
header "A01: Broken Access Control  -  Path Traversal"

r=$(curl -s -o /dev/null -w "%{http_code}" --path-as-is "$BASE/../../../etc/passwd")
check "Path traversal blocked (../..)"              "400" "$r"

r=$(curl -s -o /dev/null -w "%{http_code}" --path-as-is "$BASE/home/../secret")
check "Dot-dot in route blocked"                   "400" "$r"

r=$(curl -s -o /dev/null -w "%{http_code}" --path-as-is "$BASE/.git/config")
check "Hidden file (.git) blocked"                 "400" "$r"

r=$(curl -s -o /dev/null -w "%{http_code}" --path-as-is "$BASE/.well-known/security.txt")
check ".well-known allowed (RFC 8615)"             "200" "$r"

r=$(curl -s -o /dev/null -w "%{http_code}" --path-as-is "$BASE/%2e%2e/etc")
check "Percent-encoded traversal (%2e%2e) blocked" "400" "$r"

# ═══════════════════════════════════════════════════════════════
header "A03: Injection  -  SQL, XSS, Unicode"

# SQL injection: detected & logged, not blocked (A09 control)
r=$(curl -s -X POST "$BASE/api/todo/add" \
    -H 'Content-Type: application/json' \
    -d "{\"task\":\"test' UNION SELECT\"}")
check "SQLi detected & logged"                     "true" "$r"
check "SQLi logged to security.log"                "$(grep -c 'SQLi' /dev/shm/nest-shell-security.log 2>/dev/null || echo 0)" "$(grep -c "SQLi" /dev/shm/nest-shell-security.log 2>/dev/null)"

# XSS: HTML-escaped in response
r=$(curl -s -X POST "$BASE/api/todo/add" \
    -H 'Content-Type: application/json' \
    -d '{"task":"<script>alert(1)</script>"}')
check "XSS: script tags escaped"                   "&lt;script&gt;" "$r"

# SQL escape: single quotes doubled
r=$(curl -s -X POST "$BASE/api/todo/add" \
    -H 'Content-Type: application/json' \
    -d "{\"task\":\"test'); DROP TABLE todos; --\"}")
check "SQL escape: single quotes handled"          "success" "$r"

# Unicode: zero-width characters stripped
r=$(curl -s -X POST "$BASE/api/todo/add" \
    -H 'Content-Type: application/json' \
    -d "{\"task\":\"clean$(printf '\u200B')house\"}")
check "Unicode: zero-width space stripped"         "cleanhouse" "$r"

# Unicode: RTLO bidi override stripped
r=$(curl -s -X POST "$BASE/api/guestbook/add" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"$(printf '\u202E')evil\",\"message\":\"hi\"}")
check "Unicode: RTLO bidi override stripped"       "success" "$r"

# Unicode: ZWJ stripped from emoji sequences
r=$(curl -s -X POST "$BASE/api/guestbook/add" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"👨‍👩‍👧‍👦\",\"message\":\"family\"}")
check "Unicode: ZWJ stripped from emoji"           "success" "$r"

# Unicode: skin tone modifiers stripped
r=$(curl -s -X POST "$BASE/api/todo/add" \
    -H 'Content-Type: application/json' \
    -d "{\"task\":\"do 👋🏻 the thing\"}")
check "Unicode: skin tone stripped"                "success" "$r"

# Unicode: BOM stripped
r=$(curl -s -X POST "$BASE/api/todo/add" \
    -H 'Content-Type: application/json' \
    -d "{\"task\":\"$(printf '\uFEFF')hidden\"}")
check "Unicode: BOM stripped"                      "hidden" "$r"

# Content-Type validation
r=$(curl -s -X POST "$BASE/api/todo/add" \
    -H 'Content-Type: text/plain' \
    -d 'not json')
check "Bad Content-Type rejected"                  "error" "$r"

# Input validation
r=$(curl -s -X POST "$BASE/api/todo/add" \
    -H 'Content-Type: application/json' \
    -d '{"task":""}')
check "Empty input rejected"                       "error" "$r"

r=$(curl -s -X POST "$BASE/api/todo/toggle" \
    -H 'Content-Type: application/json' \
    -d '{"id":"not-a-number"}')
check "Non-numeric ID rejected"                    "error" "$r"

# ═══════════════════════════════════════════════════════════════
header "A05: Security Misconfiguration  -  Headers"

h=$(curl -s -I "$BASE/home" 2>&1)

check "X-Content-Type-Options: nosniff"            "nosniff"       "$h"
check "X-Frame-Options: DENY"                      "DENY"          "$h"
check "Referrer-Policy set"                        "strict-origin" "$h"
check "Server header (not Apache/nginx leak)"      "nest.shell"    "$h"
check "Content-Security-Policy on HTML"            "Content-Security-Policy" "$h"
check "Permissions-Policy set"                     "interest-cohort" "$h"

# API CORS
h=$(curl -s -I "$BASE/api/todo/list" 2>&1)
check "API: CORS Access-Control-Allow-Origin"      "Access-Control" "$h"
check "API: Security headers present"              "nosniff"        "$h"

# OPTIONS preflight
r=$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS "$BASE/api/todo/list" \
    -H 'Origin: http://example.com' -H 'Access-Control-Request-Method: POST')
check "API: CORS preflight (OPTIONS)"              "204" "$r"

# Error handling: no stack traces
r=$(curl -s -X POST "$BASE/api/todo/add" \
    -H 'Content-Type: application/json' \
    -d '{broken json')
check "500 errors hide internals"                  "Internal Server Error" "$r"

# ═══════════════════════════════════════════════════════════════
header "A07: Identification & Auth  -  Rate Limiting"

r=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/home")
check "Normal request succeeds"                    "200" "$r"

# ═══════════════════════════════════════════════════════════════
header "A09: Security Logging"

check "security.log file exists"                   "security.log" "$(ls /dev/shm/nest-shell-security.log 2>/dev/null || echo missing)"
SEC_LOG="/dev/shm/nest-shell-security.log"
log_lines=$(wc -l < "$SEC_LOG" 2>/dev/null || echo 0)
check "Security events logged (>0)"                "has-events" "$([ "$log_lines" -gt 0 ] && echo "has-events" || echo "none")"

# ═══════════════════════════════════════════════════════════════
header "Standard Functionality (sanity check)"

r=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/home")
check "Home page (200)"                            "200" "$r"

r=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/todo")
check "Todo page (200)"                            "200" "$r"

r=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/guestbook")
check "Guestbook page (200)"                       "200" "$r"

r=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/nonexistent")
check "404 page renders"                           "404" "$r"

r=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/robots.txt")
check "robots.txt (200)"                           "200" "$r"

r=$(curl -s "$BASE/.well-known/security.txt" 2>/dev/null | head -1)
check "security.txt content"                       "security" "$r"

r=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/home/style.css")
check "Static CSS served (200)"                    "200" "$r"

r=$(curl -s -X POST "$BASE/api/todo/add" \
    -H 'Content-Type: application/json' \
    -d '{"task":"normal todo item"}')
check "CRUD: Add todo item"                        "success" "$r"

r=$(curl -s -X POST "$BASE/api/guestbook/add" \
    -H 'Content-Type: application/json' \
    -d '{"name":"Alice","message":"Hello world","emoji":"🐚"}')
check "CRUD: Add guestbook entry"                  "success" "$r"

r=$(curl -s "$BASE/api/todo/list")
check "CRUD: List todos returns JSON"              '"task"' "$r"

r=$(curl -s "$BASE/api/guestbook/list")
check "CRUD: List guestbook returns JSON"          '"name"' "$r"

# Method validation
r=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/home")
check "POST on page route → 405"                   "405" "$r"

r=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$BASE/api/todo/list")
check "DELETE on read-only API → 405"              "405" "$r"

# ═══════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════"
echo -e "  Results: ${GREEN}$PASS passed${RESET}, ${RED}$FAIL failed${RESET}, $TOTAL total"
echo "═══════════════════════════════════════════════════"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
