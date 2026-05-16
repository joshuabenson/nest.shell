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
log "delete.api.sh: Received: $post_data"

id=$(echo "$post_data" | jq -r '.id // empty')

if ! is_positive_int "$id"; then
    log "delete.api.sh: Invalid id: $id"
    respond json '{"error": "Invalid todo ID"}' 400
    exit 0
fi

sqlite3 "$DB_FILE" "DELETE FROM todos WHERE id = $id" 2>&1 || {
    log "delete.api.sh: DB delete failed"
    respond json '{"error": "Failed to delete todo"}' 500
    exit 1
}

log "delete.api.sh: Deleted todo $id"
respond json '{"success": true}'
