#!/bin/bash
# utils/respond.sh  -  HTTP response helper (OWASP-hardened)

# Source security headers if available
if [ -f "$(dirname "$0")/security.sh" ]; then
    source "$(dirname "$0")/security.sh" 2>/dev/null || true
fi

# Default security headers if not sourced from security.sh
: "${SECURITY_HEADERS:=X-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\nServer: nest.shell\r\n}"

respond() {
    local content_type="$1"
    local content="$2"
    local status_code="${3:-200}"
    local status_text

    case $status_code in
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

    if [ "$status_code" = "204" ]; then
        content=""
    fi

    case $content_type in
        json) mime_type="application/json; charset=utf-8" ;;
        html) mime_type="text/html; charset=utf-8" ;;
        text) mime_type="text/plain; charset=utf-8" ;;
        *)    mime_type="application/octet-stream" ;;
    esac

    echo -ne "HTTP/1.1 $status_code $status_text\r\n\
Content-Type: $mime_type\r\n\
${SECURITY_HEADERS}\
Access-Control-Allow-Origin: *\r\n\
Content-Length: ${#content}\r\n\
Connection: close\r\n\
\r\n\
$content"
}
