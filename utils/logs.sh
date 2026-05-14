# utils/logs.sh  -  file-based logging
# LOG_FILE should be set before sourcing, or defaults to server.logs
LOG_FILE="${LOG_FILE:-server.logs}"

log() {
    printf '%s\n' "$*" >> "$LOG_FILE"
}
