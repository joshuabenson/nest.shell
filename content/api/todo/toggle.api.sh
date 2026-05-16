#!/bin/bash
set -euo pipefail

source utils/logs.sh
source utils/respond.sh
source utils/escape.sh

if [ "$HTTP_METHOD" != "POST" ]; then
    respond json '{"error": "Method not allowed"}' 405
    exit 0
fi

post_data=$(cat)
log "toggle.api.sh: Received: $post_data"

id=$(echo "$post_data" | jq -r '.id // empty')

# Validate ID
if ! is_positive_int "$id"; then
    log "toggle.api.sh: Invalid id: $id"
    respond json '{"error": "Invalid todo ID"}' 400
    exit 0
fi

sqlite3 "$DB_FILE" "UPDATE todos SET completed = NOT completed WHERE id = $id" 2>&1 || {
    log "toggle.api.sh: DB update failed"
    respond json '{"error": "Failed to toggle todo"}' 500
    exit 1
}

log "toggle.api.sh: Toggled todo $id"
respond json '{"success": true}'
