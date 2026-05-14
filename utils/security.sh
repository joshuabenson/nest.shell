#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  utils/security.sh  -  OWASP hardening for nest.shell
#  Covers: A01, A03, A05, A07, A09
# ═══════════════════════════════════════════════════════════════

# ─── Configuration ──────────────────────────────────────────
SECURITY_LOG="${SECURITY_LOG:-/dev/shm/nest-shell-security.log}"
RATE_LIMIT_DIR="${RATE_LIMIT_DIR:-./cache/ratelimit}"
MAX_REQUESTS_PER_MIN=${MAX_REQUESTS_PER_MIN:-60}
MAX_BODY_SIZE=${MAX_BODY_SIZE:-65536}        # 64KB max request body
CSRF_SECRET="${CSRF_SECRET:-}"

# Generate a CSRF secret if none set (persist across restarts)
if [ -z "$CSRF_SECRET" ]; then
    CSRF_FILE="./cache/.csrf_secret"
    if [ -f "$CSRF_FILE" ]; then
        CSRF_SECRET=$(cat "$CSRF_FILE")
    else
        CSRF_SECRET=$(od -An -N16 -x /dev/urandom | tr -d ' ')
        mkdir -p "$(dirname "$CSRF_FILE")"
        echo "$CSRF_SECRET" > "$CSRF_FILE"
        chmod 600 "$CSRF_FILE"
    fi
fi

mkdir -p "$RATE_LIMIT_DIR"

# ─── Security logging ───────────────────────────────────────
sec_log() {
    local level="$1"; shift
    local msg="$*"
    printf '[%s] [SEC:%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$level" "$msg" >> "$SECURITY_LOG"
}

# ─── A01: Path traversal protection ─────────────────────────
sanitize_route() {
    local route="$1"

    # Reject null bytes (bash globs truncate at \0, so skip glob check;
    # null bytes in HTTP request lines are already handled by read)

    # Reject percent-encoded path traversal attempts
    if [[ "$route" =~ %2[Ee]|%2[Ff]|%5[Cc] ]]; then
        sec_log "WARN" "Percent-encoded traversal attempt: $route"
        return 1
    fi

    # Normalize: collapse multiple slashes, resolve . and ..
    local normalized
    normalized=$(echo "$route" | sed 's#//\+#/#g')

    # Reject ../ path traversal
    if [[ "$normalized" == *..* ]]; then
        sec_log "WARN" "Path traversal attempt: $normalized"
        return 1
    fi

    # Reject access to hidden files/dirs (starting with .)
    # Exceptions: .well-known (RFC 8615)
    local seg
    while IFS='/' read -ra segs; do
        for seg in "${segs[@]}"; do
            if [[ "$seg" == .* ]] && [ -n "$seg" ] && [ "$seg" != ".well-known" ]; then
                sec_log "WARN" "Hidden file access attempt: $normalized"
                return 1
            fi
        done
    done <<< "$normalized"

    echo "$normalized"
    return 0
}

# ─── A03: Additional injection hardening ────────────────────
# Validate Content-Type for POST/PUT requests
validate_content_type() {
    local method="$1"
    local headers="$2"

    if [ "$method" = "POST" ] || [ "$method" = "PUT" ] || [ "$method" = "PATCH" ]; then
        # Only accept application/json for API endpoints
        if ! echo "$headers" | grep -qi 'Content-Type: application/json'; then
            return 1
        fi
    fi
    return 0
}

# ─── A05: Security headers ──────────────────────────────────
# Applied to every HTTP response
SECURITY_HEADERS="X-Content-Type-Options: nosniff\r\n\
X-Frame-Options: DENY\r\n\
X-XSS-Protection: 0\r\n\
Referrer-Policy: strict-origin-when-cross-origin\r\n\
Permissions-Policy: interest-cohort=()\r\n\
Server: nest.shell\r\n"

# Content-Security-Policy for HTML pages
CSP_HEADER="Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.tailwindcss.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'\r\n"

emit_security_headers() {
    echo -ne "$SECURITY_HEADERS"
}

emit_csp_header() {
    echo -ne "$CSP_HEADER"
}

# ─── A07: CSRF protection ───────────────────────────────────
# Generate a CSRF token for forms
generate_csrf_token() {
    local session_id="$1"
    local raw="${CSRF_SECRET}:${session_id}:$(date +%s)"
    echo -n "$raw" | sha256sum | cut -d' ' -f1
}

# Verify a CSRF token
verify_csrf_token() {
    local token="$1"
    local session_id="$2"
    local expected
    expected=$(generate_csrf_token "$session_id")
    [ "$token" = "$expected" ]
}

# ─── A07: Rate limiting ─────────────────────────────────────
# Simple token-bucket rate limiter using filesystem
check_rate_limit() {
    local client_ip="$1"
    local limit="${2:-$MAX_REQUESTS_PER_MIN}"
    local window=60  # seconds

    # Hash the IP for a safe filename
    local ip_hash
    ip_hash=$(echo -n "$client_ip" | sha256sum | cut -c1-16)
    local bucket_file="$RATE_LIMIT_DIR/$ip_hash"

    local now
    now=$(date +%s)
    local old_count=0
    local old_time=$now

    if [ -f "$bucket_file" ]; then
        read -r old_count old_time < "$bucket_file"
    fi

    # Reset if window has passed
    if [ $((now - old_time)) -gt $window ]; then
        old_count=0
        old_time=$now
    fi

    local new_count=$((old_count + 1))

    if [ "$new_count" -gt "$limit" ]; then
        sec_log "WARN" "Rate limit exceeded: $client_ip ($new_count req/min)"
        return 1
    fi

    echo "$new_count $old_time" > "$bucket_file"
    return 0
}

# ─── A09: Security monitoring helpers ───────────────────────
# Detect and log SQL injection patterns in input
detect_sqli_attempt() {
    local input="$1"
    local source="$2"
    
    # Common SQL injection patterns
    if echo "$input" | grep -qiE "(union.*select|drop\s+table|--\s*$|;\s*$|/\*|\*/|exec\s*\(|xp_cmdshell)"; then
        sec_log "ALERT" "Possible SQLi in $source: ${input:0:100}"
        return 0
    fi
    return 1
}

# Extract client IP from socat environment
get_client_ip() {
    # socat sets SOCAT_PEERADDR
    echo "${SOCAT_PEERADDR:-127.0.0.1}"
}
