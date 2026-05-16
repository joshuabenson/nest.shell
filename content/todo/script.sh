#!/bin/bash
source utils/escape.sh

echo "<ul id='todo-list' class='mt-4'>"
sqlite3 "./app.db" "SELECT id, task, completed FROM todos ORDER BY id DESC" | while IFS='|' read -r id task completed; do
    safe_task=$(html_escape "$task")
    completed_class=""
    toggle_text="Complete"
    if [ "$completed" = "1" ]; then
        completed_class="line-through text-gray-500"
        toggle_text="Undo"
    fi
    echo "<li class='flex items-center justify-between p-2 border-b'>"
    echo "  <span class='$completed_class'>"
    echo "    $safe_task"
    echo "  </span>"
    echo "  <div>"
    echo "    <button onclick='toggleTodo($id)' class='text-blue-500 hover:text-blue-700 mr-2'>"
    echo "      $toggle_text"
    echo "    </button>"
    echo "    <button onclick='deleteTodo($id)' class='text-red-500 hover:text-red-700'>"
    echo "      Delete"
    echo "    </button>"
    echo "  </div>"
    echo "</li>"
done
echo "</ul>"
