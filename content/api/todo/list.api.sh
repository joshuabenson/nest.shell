#!/bin/bash
set -euo pipefail

source utils/logs.sh
source utils/respond.sh

log "list.api.sh: Fetching todos"

if [ "$HTTP_METHOD" != "GET" ] && [ "$HTTP_METHOD" != "" ]; then
    respond json '{"error": "Method not allowed"}' 405
    exit 0
fi

todos=$(sqlite3 "$DB_FILE" "SELECT id, task, completed FROM todos ORDER BY id DESC" -json 2>&1) || {
    log "list.api.sh: DB error: $todos"
    respond json '{"error": "Database error"}' 500
    exit 1
}

log "list.api.sh: Todos fetched successfully"
respond json "$todos"
