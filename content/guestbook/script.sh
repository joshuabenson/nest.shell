#!/bin/bash
source utils/escape.sh

# Render guestbook entries
echo "<div id='guestbook-entries' class='space-y-4'>"
entries=$(sqlite3 "./app.db" "SELECT name, message, emoji, created_at FROM guestbook ORDER BY id DESC LIMIT 50" 2>/dev/null)

if [ -z "$entries" ]; then
    echo "<p class='text-gray-400 italic py-8 text-center'>No messages yet — be the first to sign! 🐚</p>"
else
    echo "$entries" | while IFS='|' read -r name message emoji created_at; do
        safe_name=$(html_escape "$name")
        safe_message=$(html_escape "$message")
        safe_date=$(html_escape "$created_at")
        echo "<div class='bg-gray-50 rounded-lg p-4 border border-gray-100 hover:border-gray-200 transition'>"
        echo "  <div class='flex items-start gap-3'>"
        echo "    <span class='text-3xl'>$emoji</span>"
        echo "    <div class='flex-1'>"
        echo "      <p class='font-semibold text-gray-800'>$safe_name</p>"
        echo "      <p class='text-gray-600 mt-1'>$safe_message</p>"
        echo "      <p class='text-xs text-gray-400 mt-2'>$safe_date</p>"
        echo "    </div>"
        echo "  </div>"
        echo "</div>"
    done
fi
echo "</div>"
