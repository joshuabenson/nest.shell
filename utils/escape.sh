#!/bin/bash
# utils/escape.sh  -  Input sanitization & escaping
# Covers: A03 (Injection), A07 (CSRF tokens)

# ─── Unicode sanitization: strip dangerous invisible characters ──
# Covers: zero-width chars, bidi overrides, control chars, variation selectors
# These can be used for: log spoofing (RTLO), content filter bypass, steganography
strip_unsafe_unicode() {
    local val="$1"
    # Use sed to remove dangerous Unicode ranges (UTF-8 encoded patterns):
    # E2 80 8B = U+200B ZERO WIDTH SPACE
    # E2 80 8C = U+200C ZERO WIDTH NON-JOINER
    # E2 80 8D = U+200D ZERO WIDTH JOINER
    # E2 80 8E = U+200E LEFT-TO-RIGHT MARK
    # E2 80 8F = U+200F RIGHT-TO-LEFT MARK
    # E2 80 AA-E2 80 AE = U+202A-U+202E BIDI OVERRIDES
    # E2 81 A0-E2 81 AF = U+2060-U+206F GENERAL PUNCTUATION (word joiner, etc.)
    # EF BB BF = U+FEFF BOM / ZERO WIDTH NO-BREAK SPACE
    # EF B8 8F = U+FE0F VARIATION SELECTOR-16 (emoji style)
    # F0 9F 8F BB-F0 9F 8F BF = U+1F3FB-U+1F3FF skin tones (kept, but could be stripped)
    echo "$val" | sed \
        -e 's/\xE2\x80\x8B//g' \
        -e 's/\xE2\x80\x8C//g' \
        -e 's/\xE2\x80\x8D//g' \
        -e 's/\xE2\x80\x8E//g' \
        -e 's/\xE2\x80\x8F//g' \
        -e 's/\xE2\x80\xAA//g' \
        -e 's/\xE2\x80\xAB//g' \
        -e 's/\xE2\x80\xAC//g' \
        -e 's/\xE2\x80\xAD//g' \
        -e 's/\xE2\x80\xAE//g' \
        -e 's/\xE2\x81\xA0//g' \
        -e 's/\xE2\x81\xA1//g' \
        -e 's/\xE2\x81\xAA//g' \
        -e 's/\xE2\x81\xAB//g' \
        -e 's/\xEF\xBB\xBF//g' \
        -e 's/\xEF\xB8\x8F//g' \
        -e 's/\xEF\xB8\x8E//g' \
        -e 's/\xF0\x9F\x8F\xBB//g' \
        -e 's/\xF0\x9F\x8F\xBC//g' \
        -e 's/\xF0\x9F\x8F\xBD//g' \
        -e 's/\xF0\x9F\x8F\xBE//g' \
        -e 's/\xF0\x9F\x8F\xBF//g'
}

# ─── SQL escaping for SQLite ────────────────────────────────
# Returns the value with single quotes doubled.
# Also strips unsafe unicode and null bytes.
sql_escape() {
    local val="$1"
    val=$(strip_unsafe_unicode "$val")
    val="${val//$'\0'/}"
    echo "${val//\'/\'\'}"
}

# ─── HTML entity escaping ───────────────────────────────────
html_escape() {
    local val="$1"
    val=$(strip_unsafe_unicode "$val")
    val="${val//$'\0'/}"
    echo "$val" | sed '
        s/&/\&amp;/g
        s/</\&lt;/g
        s/>/\&gt;/g
        s/"/\&quot;/g
        s/'"'"'/\&#39;/g
    '
}

# ─── Shell command argument escaping ────────────────────────
# Safe for use in eval or command substitution
shell_escape() {
    local val="$1"
    printf '%q' "$val"
}

# ─── Input length limits ────────────────────────────────────
MAX_NAME_LEN=50
MAX_MESSAGE_LEN=500
MAX_TASK_LEN=500

# Validate that a value is a positive integer.
is_positive_int() {
    local val="$1"
    val="${val//$'\0'/}"
    val=$(strip_unsafe_unicode "$val")
    [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -gt 0 ] && [ "$val" -le 2147483647 ]
}

# Validate trimmed text is non-empty and within length limit.
is_valid_text() {
    local val="$1"
    local max_len="${2:-$MAX_TASK_LEN}"
    val="${val//$'\0'/}"
    val=$(strip_unsafe_unicode "$val")
    val=$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$val" ] && [ "${#val}" -le "$max_len" ] && [ "${#val}" -ge 1 ]
}

# Validate a name field.
is_valid_name() {
    local val="$1"
    val="${val//$'\0'/}"
    val=$(strip_unsafe_unicode "$val")
    val=$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$val" ] && [ "${#val}" -le "$MAX_NAME_LEN" ]
}

# ─── CSRF token helpers ─────────────────────────────────────
# Generate a simple token (used in forms)
make_csrf_token() {
    local seed="${1:-$(date +%s)}"
    local raw="${CSRF_SECRET:-s3cret}:${seed}"
    echo -n "$raw" | sha256sum 2>/dev/null | cut -d' ' -f1 || echo -n "$raw" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "dev-token"
}

check_csrf() {
    local token="$1"
    local seed="$2"
    local expected
    expected=$(make_csrf_token "$seed")
    [ "$token" = "$expected" ]
}
