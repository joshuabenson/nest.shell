function renderGuestbook(entries) {
    const container = document.getElementById('guestbook-entries');
    if (!entries || entries.length === 0) {
        container.innerHTML = '<p class="text-gray-400 italic py-8 text-center">No messages yet — be the first to sign! 🐚</p>';
        return;
    }
    container.innerHTML = entries.map(e => `
        <div class="bg-gray-50 rounded-lg p-4 border border-gray-100 hover:border-gray-200 transition">
            <div class="flex items-start gap-3">
                <span class="text-3xl">${e.emoji}</span>
                <div class="flex-1">
                    <p class="font-semibold text-gray-800">${e.name}</p>
                    <p class="text-gray-600 mt-1">${e.message}</p>
                    <p class="text-xs text-gray-400 mt-2">${e.created_at}</p>
                </div>
            </div>
        </div>
    `).join('');
}

function fetchAndRenderGuestbook() {
    fetch('/api/guestbook/list')
        .then(r => r.json())
        .then(entries => renderGuestbook(entries))
        .catch(err => console.error('Error fetching guestbook:', err));
}

function addGuestbookEntry() {
    const name = document.getElementById('guest-name').value.trim();
    const message = document.getElementById('guest-message').value.trim();
    const emoji = document.getElementById('guest-emoji').value;

    if (!name || !message) {
        alert('Please fill in your name and message!');
        return;
    }

    fetch('/api/guestbook/add', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, message, emoji })
    })
    .then(r => r.json())
    .then(() => {
        document.getElementById('guest-name').value = '';
        document.getElementById('guest-message').value = '';
        fetchAndRenderGuestbook();
    })
    .catch(err => console.error('Error adding entry:', err));
}

// Auto-load on page
document.addEventListener('DOMContentLoaded', fetchAndRenderGuestbook);
