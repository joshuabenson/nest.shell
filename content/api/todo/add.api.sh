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

# Read the POST body
post_data=$(cat)
log "add.api.sh: Received POST data: $post_data"

# A09: SQLi detection
if detect_sqli_attempt "$post_data" "todo/add.api.sh" 2>/dev/null; then
    sec_log "ALERT" "SQLi detected in todo/add — request logged"
fi

# Extract the task using jq
task=$(echo "$post_data" | jq -r '.task // empty')
log "add.api.sh: Extracted task: $task"

# Validate input
if ! is_valid_text "$task" 500; then
    log "add.api.sh: Invalid task text (empty or too long)"
    respond json '{"error": "Task must be 1-500 characters"}' 400
    exit 0
fi

# Escape for SQL and HTML safety
safe_task=$(sql_escape "$task")

# Insert into database
sqlite3 "$DB_FILE" "INSERT INTO todos (task) VALUES ('$safe_task')" 2>&1 || {
    log "add.api.sh: Database insert failed: $?"
    respond json '{"error": "Failed to add task"}' 500
    exit 1
}

log "add.api.sh: Task inserted successfully"
respond json '{"success": true, "task": "'"$(html_escape "$task")"'"}'
