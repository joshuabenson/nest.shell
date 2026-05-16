#!/bin/bash
set -euo pipefail

source utils/logs.sh
source utils/respond.sh
source utils/escape.sh

log "guestbook/list: Fetching entries"

if [ "$HTTP_METHOD" != "GET" ] && [ "$HTTP_METHOD" != "" ]; then
    respond json '{"error": "Method not allowed"}' 405
    exit 0
fi

entries=$(sqlite3 "$DB_FILE" "SELECT id, name, message, emoji, created_at FROM guestbook ORDER BY id DESC LIMIT 50" 2>&1) || {
    log "guestbook/list: DB error: $entries"
    respond json '{"error": "Database error"}' 500
    exit 1
}

# Build a proper JSON array from the pipe-delimited output
if [ -z "$entries" ]; then
    respond json '[]'
else
    json_array="["
    first=true
    while IFS='|' read -r id name message emoji created_at; do
        safe_name=$(html_escape "$name")
        safe_message=$(html_escape "$message")
        if $first; then
            first=false
        else
            json_array+=","
        fi
        json_array+="{\"id\":$id,\"name\":\"$safe_name\",\"message\":\"$safe_message\",\"emoji\":\"$emoji\",\"created_at\":\"$created_at\"}"
    done <<< "$entries"
    json_array+="]"
    respond json "$json_array"
fi
