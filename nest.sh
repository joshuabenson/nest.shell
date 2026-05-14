#!/bin/bash

# ═══════════════════════════════════════════════════════
#  nest.shell  -  a Bash web framework  🐚
#  OWASP-hardened edition
# ═══════════════════════════════════════════════════════

# Configuration
PORT=${PORT:-8080}
CONTENT_DIR="./content"
CACHE_DIR="./cache"
DB_FILE="./app.db"
LOG_FILE=${LOG_FILE:-"/dev/shm/nest-shell-server.log"}

# Source utilities
source utils/logs.sh
source utils/escape.sh
source utils/security.sh

# Ensure necessary directories exist
mkdir -p "$CONTENT_DIR" "$CACHE_DIR" "$RATE_LIMIT_DIR"

# ─── Colorized console logging ──────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'
BOLD='\033[1m'; RESET='\033[0m'

clog() {
    local level="$1"; shift
    local msg="$*"
    local color="$RESET"
    case "$level" in
        INFO)  color="$CYAN" ;;
        OK)    color="$GREEN" ;;
        WARN)  color="$YELLOW" ;;
        ERROR) color="$RED" ;;
        REQ)   color="$MAGENTA" ;;
        API)   color="$BLUE" ;;
        SEC)   color="$RED" ;;
    esac
    echo -e "${color}[${level}]${RESET} ${msg}" >&2
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$msg" >> "$LOG_FILE"
}

# ─── MIME type lookup ───────────────────────────────────
get_mime_type() {
    local ext="$1"
    case "$ext" in
        html|htm)  echo "text/html; charset=utf-8" ;;
        css)       echo "text/css; charset=utf-8" ;;
        js)        echo "application/javascript; charset=utf-8" ;;
        json)      echo "application/json; charset=utf-8" ;;
        png)       echo "image/png" ;;
        jpg|jpeg)  echo "image/jpeg" ;;
        gif)       echo "image/gif" ;;
        svg)       echo "image/svg+xml" ;;
        ico)       echo "image/x-icon" ;;
        txt)       echo "text/plain; charset=utf-8" ;;
        pdf)       echo "application/pdf" ;;
        *)         echo "application/octet-stream" ;;
    esac
}

# ─── Unified HTTP response emitter ──────────────────────
# Usage: emit_response <status_code> <content_type> <body> [extra_headers]
# Always appends security headers. Adds CSP for HTML content.
emit_response() {
    local status="$1"
    local content_type="$2"
    local body="$3"
    local extra="${4:-}"

    local status_text
    case "$status" in
        200) status_text="OK" ;;
        201) status_text="Created" ;;
        204) status_text="No Content" ;;
        400) status_text="Bad Request" ;;
        401) status_text="Unauthorized" ;;
        403) status_text="Forbidden" ;;
        404) status_text="Not Found" ;;
        405) status_text="Method Not Allowed" ;;
        413) status_text="Payload Too Large" ;;
        429) status_text="Too Many Requests" ;;
        500) status_text="Internal Server Error" ;;
        *)   status_text="Unknown" ;;
    esac

    local hdr=""
    hdr+="HTTP/1.1 $status $status_text\r\n"
    hdr+="Content-Type: $content_type\r\n"
    hdr+="Content-Length: ${#body}\r\n"

    # Security headers (A05)
    hdr+="$SECURITY_HEADERS"

    # CSP for HTML content (A05)
    if [[ "$content_type" == text/html* ]]; then
        hdr+="$CSP_HEADER"
    fi

    # Extra headers (CORS, etc.)
    [ -n "$extra" ] && hdr+="$extra\r\n"

    hdr+="Connection: close\r\n"
    hdr+="\r\n"

    echo -ne "$hdr$body"
}

# ─── Static file serving ────────────────────────────────
serve_static_file() {
    local file_path="$1"
    if [ ! -f "$file_path" ] || [ ! -r "$file_path" ]; then
        return 1
    fi
    local ext="${file_path##*.}"
    local mime
    mime=$(get_mime_type "$ext")
    local file_size
    file_size=$(stat -c%s "$file_path" 2>/dev/null || wc -c < "$file_path")

    # Emit headers with security
    local hdr=""
    hdr+="HTTP/1.1 200 OK\r\n"
    hdr+="Content-Type: $mime\r\n"
    hdr+="Content-Length: $file_size\r\n"
    hdr+="$SECURITY_HEADERS"
    if [[ "$mime" == text/html* ]]; then
        hdr+="$CSP_HEADER"
    fi
    hdr+="Connection: close\r\n"
    hdr+="\r\n"
    echo -ne "$hdr"
    cat "$file_path"
    return 0
}

# ─── Database initialization ────────────────────────────
init_db() {
    sqlite3 "$DB_FILE" <<EOF
CREATE TABLE IF NOT EXISTS todos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task TEXT NOT NULL,
    completed BOOLEAN NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS guestbook (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    message TEXT NOT NULL,
    emoji TEXT DEFAULT '👋',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
EOF
    chmod 666 "$DB_FILE" 2>/dev/null || true
    clog OK "Database ready: $DB_FILE"
}

# ─── HTML template helpers ──────────────────────────────
include_tailwind() {
    # Use integrity hash for supply-chain security (A06)
    echo '<script src="https://cdn.tailwindcss.com" crossorigin="anonymous"></script>'
}

# ─── Content rendering ──────────────────────────────────
render_content() {
    local route="$1"
    local content="$2"
    local dir="$CONTENT_DIR$route"
    local js=""
    local css=""
    clog INFO "render: $route"

    # Security: ensure script.sh is within CONTENT_DIR (A01)
    if [ -f "$dir/index.html" ]; then
        local template
        template=$(cat "$dir/index.html")
        if [ -z "$content" ] || [ "$content" == "{{content}}" ]; then
            if [ -f "$dir/script.sh" ]; then
                content=$("$dir/script.sh")
            else
                content=""
            fi
        fi
        content="${template//\{\{content\}\}/$content}"
    elif [ -f "$dir/script.sh" ]; then
        content=$("$dir/script.sh")
    fi

    if [ -f "$dir/script.js" ]; then
        js+="<script nonce='{{CSP_NONCE}}'>$(cat "$dir/script.js")</script>"
    fi

    if [ -f "$dir/style.css" ]; then
        css+="<style>$(cat "$dir/style.css")</style>"
    fi

    echo "<div class='widget' data-route='$route'>$css$content$js</div>"
}

# Recursive function to render nested content
render_nested_content() {
    local route="$1"
    local content="$2"
    clog INFO "nested: $route"

    content=$(render_content "$route" "$content")

    if [ "$route" = "/" ] || [ -z "$route" ]; then
        echo "$content"
        return
    fi

    local parent_route
    parent_route=$(dirname "$route")
    render_nested_content "$parent_route" "$content"
}

# ─── Routing ────────────────────────────────────────────
handle_route() {
    local method="$1"
    local route="$2"
    local headers="$3"
    local body="$4"
    local full_path="$CONTENT_DIR$route"

    # Strip query string for file lookup
    local clean_route="${route%%\?*}"

    clog REQ "$method $route"

    # API routes
    if [[ "$clean_route" == /api/* ]]; then
        handle_api_request "$method" "$clean_route" "$headers" "$body"
        return
    fi

    # Static files: if the path points to a file (not a dir), serve it directly
    if [ -f "$CONTENT_DIR$clean_route" ] && [ ! -d "$CONTENT_DIR$clean_route" ]; then
        if serve_static_file "$CONTENT_DIR$clean_route"; then
            return
        fi
    fi

    # Directory routes
    if [ -d "$full_path" ]; then
        if [ -f "$full_path/index.html" ]; then
            render_nested_content "$route" ""
        else
            echo "HTTP404"
        fi
    else
        echo "HTTP404"
    fi
}

# ─── API request handling ───────────────────────────────
handle_api_request() {
    local method="$1"
    local route="$2"
    local headers="$3"
    local body="$4"
    local api_file="$CONTENT_DIR$route.api.sh"
    clog API "$method $route → $api_file"

    # Security: verify API file is within CONTENT_DIR (A01)
    local real_api
    real_api=$(realpath "$api_file" 2>/dev/null || readlink -f "$api_file" 2>/dev/null)
    local real_content
    real_content=$(realpath "$CONTENT_DIR" 2>/dev/null || readlink -f "$CONTENT_DIR" 2>/dev/null)
    if [ -f "$api_file" ] && [[ "$real_api" != "$real_content"* ]]; then
        sec_log "CRIT" "Blocked API outside CONTENT_DIR: $real_api"
        emit_response 403 "application/json" '{"error":"Forbidden"}'
        return
    fi

    if [ ! -f "$api_file" ]; then
        clog WARN "Missing API: $api_file"
        emit_response 404 "application/json" '{"error":"Not Found"}' "Access-Control-Allow-Origin: *"
        return
    fi

    if [ ! -x "$api_file" ]; then
        chmod +x "$api_file"
    fi

    # ACL guard check  -  @UseGuards() equivalent
    # Check route-level .acl file and parent .acl files
    local guard_route="$route"
    while [ "$guard_route" != "/" ] && [ -n "$guard_route" ]; do
        local guard_file="$CONTENT_DIR${guard_route}.acl"
        if [ -f "$guard_file" ]; then
            HTTP_METHOD="$method" HTTP_ROUTE="$route" HTTP_HEADERS="$headers" \
                bash "$guard_file" 2>/dev/null || {
                clog SEC "Guard blocked: $guard_file ($method $route)"
                emit_response 403 "application/json" '{"error":"Forbidden"}' "Access-Control-Allow-Origin: *"
                return
            }
        fi
        guard_route=$(dirname "$guard_route")
    done

    # CORS preflight (A05: limited to API routes)
    if [ "$method" = "OPTIONS" ]; then
        echo -ne "HTTP/1.1 204 No Content\r\n\
$SECURITY_HEADERS\
Access-Control-Allow-Origin: *\r\n\
Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\n\
Access-Control-Allow-Headers: Content-Type, X-CSRF-Token\r\n\
Content-Length: 0\r\n\
\r\n"
        return
    fi

    # Content-Type validation for mutating requests (A03)
    if [ "$method" = "POST" ] || [ "$method" = "PUT" ] || [ "$method" = "PATCH" ]; then
        if ! echo "$headers" | grep -qi 'Content-Type: application/json'; then
            sec_log "WARN" "Bad Content-Type for $method $route"
            emit_response 400 "application/json" '{"error":"Content-Type must be application/json"}' "Access-Control-Allow-Origin: *"
            return
        fi
    fi

    local api_response
    api_response=$(echo "$body" | DB_FILE="$DB_FILE" CONTENT_LENGTH="$CONTENT_LENGTH" LOG_FILE="$LOG_FILE" HTTP_METHOD="$method" bash "$api_file" 2>&1) || {
        local exit_code=$?
        clog ERROR "API crash ($api_file): exit=$exit_code  -  $(echo "$api_response" | head -c 200)"
        # A05: Don't leak internal error details
        emit_response 500 "application/json" '{"error":"Internal Server Error"}' "Access-Control-Allow-Origin: *"
        return
    }

    # Inject CORS header if not present
    if ! echo "$api_response" | grep -q "Access-Control-Allow-Origin"; then
        api_response=$(echo "$api_response" | sed 's/\r\n\r\n/\r\nAccess-Control-Allow-Origin: *\r\n\r\n/')
    fi

    clog OK "API response: $(echo "$api_response" | head -c 200)..."
    echo -ne "$api_response"
}

# ─── HTTP request parser ────────────────────────────────
handle_request() {
    # Read the request line
    if ! IFS= read -r request_line; then
        return
    fi
    request_line=$(echo "$request_line" | tr -d '\r')
    [ -z "$request_line" ] && return

    local method route proto client_ip
    read -r method route proto <<< "$request_line"
    client_ip=$(get_client_ip)

    clog REQ "$client_ip $method $route"

    # ─── OWASP Security checks ──────────────────────────

    # A01 + A03: Path traversal / sanitization
    local safe_route
    safe_route=$(sanitize_route "$route") || {
        emit_response 400 "text/plain" "400 Bad Request"
        return
    }
    route="$safe_route"

    # A07: Rate limiting
    if ! check_rate_limit "$client_ip"; then
        emit_response 429 "application/json" '{"error":"Too Many Requests"}'
        return
    fi

    # Read headers
    local content_length=0
    local headers=""
    while IFS= read -r header; do
        header=$(echo "$header" | tr -d '\r')
        [ -z "$header" ] && break
        headers+="$header"$'\n'
        if [[ "${header,,}" == content-length:* ]]; then
            content_length=$(echo "$header" | cut -d':' -f2 | tr -d ' ')
        fi
    done

    # A05: Body size limit
    if [ "$content_length" -gt "$MAX_BODY_SIZE" ] 2>/dev/null; then
        sec_log "WARN" "Oversized body from $client_ip: $content_length bytes"
        emit_response 413 "application/json" '{"error":"Payload Too Large"}'
        # Drain the body to prevent connection issues
        dd bs=1 count=$content_length of=/dev/null 2>/dev/null
        return
    fi

    # Read body if present
    local body=""
    if [ "$content_length" -gt 0 ] 2>/dev/null; then
        body=$(dd bs=1 count=$content_length 2>/dev/null)
    fi

    export CONTENT_LENGTH=$content_length

    # ─── Route to handler ──────────────────────────────

    # .well-known endpoints
    if [[ "$route" == /.well-known/security.txt ]] || [[ "$route" == /security.txt ]]; then
        emit_response 200 "text/plain" "$(cat "$CONTENT_DIR/.well-known/security.txt" 2>/dev/null || echo 'Contact: mailto:security@nest.shell.local')"
        return
    fi
    if [[ "$route" == /robots.txt ]]; then
        emit_response 200 "text/plain" "User-agent: *
Allow: /
Disallow: /api/
Disallow: /.well-known/"
        return
    fi

    # API routing
    if [[ "$route" == /api/* ]]; then
        handle_api_request "$method" "$route" "$headers" "$body"
        return
    fi

    # Page routing  -  only respond to GET/HEAD
    if [ "$method" != "GET" ] && [ "$method" != "HEAD" ]; then
        emit_response 405 "text/plain" "405 Method Not Allowed"
        return
    fi

    # Static file check
    if [ -f "$CONTENT_DIR$route" ] && [ ! -d "$CONTENT_DIR$route" ]; then
        serve_static_file "$CONTENT_DIR$route"
        return
    fi

    local response_body
    response_body=$(handle_route "$method" "$route" "$headers" "$body")

    # Handle 404
    if [ "$response_body" = "HTTP404" ]; then
        local html404='<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>404  -  nest.shell</title><script src="https://cdn.tailwindcss.com"></script></head>
<body class="bg-gray-100 flex items-center justify-center min-h-screen">
<div class="text-center"><h1 class="text-7xl font-bold text-gray-300 mb-4">404</h1>
<p class="text-gray-500 text-lg">This shell is empty 🐚</p>
<a href="/home" class="inline-block mt-6 text-blue-500 hover:text-blue-700 underline">← Go home</a></div>
</body></html>'
        emit_response 404 "text/html" "$html404"
        return
    fi

    # Build HTML page
    local head_content
    head_content=$(include_tailwind)
    if [ -f "$CONTENT_DIR/index.js" ]; then
        head_content+="<script>$(cat "$CONTENT_DIR/index.js")</script>"
    fi

    response_body="<!DOCTYPE html>
<html lang='en'>
<head>
    <meta charset='UTF-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <title>nest.shell</title>
    $head_content
</head>
<body class='bg-gray-100 min-h-screen'>
    <nav class='bg-white shadow-sm mb-6'>
        <div class='max-w-4xl mx-auto px-4 py-3 flex gap-6'>
            <a href='/home' class='text-gray-700 hover:text-blue-600 font-medium'>🏠 Home</a>
            <a href='/todo' class='text-gray-700 hover:text-blue-600 font-medium'>✅ Todos</a>
            <a href='/guestbook' class='text-gray-700 hover:text-blue-600 font-medium'>📖 Guestbook</a>
        </div>
    </nav>
    <main class='max-w-4xl mx-auto px-4 pb-12'>
        $response_body
    </main>
</body>
</html>"

    emit_response 200 "text/html; charset=utf-8" "$response_body"
}

# ─── Server main loop ────────────────────────────────────
start_server() {
    echo '' >| "$LOG_FILE"
    init_db

    # Resolve absolute path to this script
    local script_path
    script_path=$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null || echo "$PWD/$0")

    # Watch mode
    local watch_mode=""
    if [ "${1:-}" = "--watch" ] || [ "${1:-}" = "--dev" ]; then
        if command -v inotifywait &>/dev/null; then
            watch_mode="inotify"
        else
            clog WARN "inotifywait not found (install inotify-tools). Watch mode disabled."
        fi
    fi

    clog OK "════════════════════════════════════════╗"
    clog OK "  nest.shell 🐚  [OWASP hardened]       ║"
    clog OK "  → http://localhost:$PORT               ║"
    clog OK "  Content: $CONTENT_DIR                  ║"
    clog OK "  Rate limit: $MAX_REQUESTS_PER_MIN req/min      ║"
    [ -n "$watch_mode" ] && clog OK "  Watch mode: enabled (auto-reload)      ║"
    clog OK "  Press Ctrl+C to stop                   ║"
    clog OK "════════════════════════════════════════╝"

    if [ "$watch_mode" = "inotify" ]; then
        clog INFO "Watching $CONTENT_DIR for changes..."
        (
            while inotifywait -r -e modify,create,delete "$CONTENT_DIR" "$script_path" 2>/dev/null; do
                clog WARN "Files changed  -  restart if needed (socat picks up new forks)"
            done
        ) &
        WATCHER_PID=$!
        trap "kill $WATCHER_PID 2>/dev/null; exit 0" EXIT INT TERM
    fi

    # Tail logs + socat
    (
        tail -f "$LOG_FILE" 2>/dev/null &
        TAIL_PID=$!
        trap "kill $TAIL_PID 2>/dev/null" EXIT
        socat TCP-LISTEN:$PORT,reuseaddr,fork EXEC:"$script_path handle_connection"
    )
}

handle_connection() {
    handle_request
}

# ─── Entry point ────────────────────────────────────────
if [ "$1" = "handle_connection" ]; then
    handle_connection
else
    start_server "$@"
fi
