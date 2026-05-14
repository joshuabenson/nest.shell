#!/bin/bash
set -euo pipefail

source utils/logs.sh
source utils/respond.sh
source utils/escape.sh
source utils/security.sh 2>/dev/null || true

if [ "$HTTP_METHOD" != "POST" ]; then
    respond json '{"error": "Method not allowed"}' 405
    exit 0
fi

post_data=$(cat)
log "guestbook/add: Received: $post_data"

# A09: SQLi detection
if detect_sqli_attempt "$post_data" "guestbook/add.api.sh" 2>/dev/null; then
    sec_log "ALERT" "SQLi detected in guestbook/add — request logged"
fi

name=$(echo "$post_data" | jq -r '.name // empty')
message=$(echo "$post_data" | jq -r '.message // empty')
emoji=$(echo "$post_data" | jq -r '.emoji // "👋"')

# Validate
if ! is_valid_text "$name" 50; then
    respond json '{"error": "Name must be 1-50 characters"}' 400
    exit 0
fi
if ! is_valid_text "$message" 500; then
    respond json '{"error": "Message must be 1-500 characters"}' 400
    exit 0
fi
# Only allow a single character that's likely an emoji or letter
if [ "${#emoji}" -gt 4 ]; then
    emoji="👋"
fi

safe_name=$(sql_escape "$name")
safe_message=$(sql_escape "$message")

sqlite3 "$DB_FILE" "INSERT INTO guestbook (name, message, emoji) VALUES ('$safe_name', '$safe_message', '$emoji')" 2>&1 || {
    log "guestbook/add: DB insert failed"
    respond json '{"error": "Failed to add entry"}' 500
    exit 1
}

log "guestbook/add: Entry added by $name"
respond json '{"success": true}'
