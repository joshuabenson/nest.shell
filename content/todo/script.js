function renderTodos(todos) {
    const todoList = document.getElementById('todo-list');
    todoList.innerHTML = todos.map(todo => `
        <li class="flex items-center justify-between p-2 border-b">
            <span class="${todo.completed ? 'line-through text-gray-500' : ''}">
                ${todo.task}
            </span>
            <div>
                <button onclick="toggleTodo(${todo.id})" class="text-blue-500 hover:text-blue-700 mr-2">
                    ${todo.completed ? 'Undo' : 'Complete'}
                </button>
                <button onclick="deleteTodo(${todo.id})" class="text-red-500 hover:text-red-700">
                    Delete
                </button>
            </div>
        </li>
    `).join('');
}

function fetchAndRenderTodos() {
    fetch('/api/todo/list')
        .then(response => response.json())
        .then(todos => renderTodos(todos))
        .catch(error => console.error('Error fetching todos:', error));
}

function addTodo() {
    const input = document.getElementById('new-todo');
    const task = input.value.trim();
    if (task) {
        fetch('/api/todo/add', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ task })
        })
        .then(response => response.json())
        .then(() => {
            input.value = '';
            fetchAndRenderTodos();
        })
        .catch(error => console.error('Error adding todo:', error));
    }
}

function toggleTodo(id) {
    console.log(`toggled: ${id}`)
    fetch('/api/todo/toggle', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id })
    })
    .then(response => response.json())
    .then(() => fetchAndRenderTodos())
    .catch(error => console.error('Error toggling todo:', error));
}

function deleteTodo(id) {
    fetch('/api/todo/delete', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id })
    })
    .then(response => response.json())
    .then(() => fetchAndRenderTodos())
    .catch(error => console.error('Error deleting todo:', error));
}

// Initial load of todos — fetch on page load
document.addEventListener('DOMContentLoaded', fetchAndRenderTodos);