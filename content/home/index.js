function init_home(widget) {
  const [count, setCount] = useState('homeCount', 0);
  const counterElement = widget.querySelector('#counter');

  function updateCounter() {
    counterElement.innerHTML = `
      <p class="text-3xl font-bold text-gray-700">${count}</p>
      <p class="text-xs text-gray-400 mt-1">button clicks</p>
    `;
  }

  useEffect(updateCounter, ['homeCount']);

  const btnGroup = document.createElement('div');
  btnGroup.className = 'flex gap-2 justify-center mt-3';

  const incrementButton = document.createElement('button');
  incrementButton.textContent = '+';
  incrementButton.className = 'bg-blue-500 hover:bg-blue-600 text-white w-10 h-10 rounded-full text-xl font-bold transition shadow';
  incrementButton.addEventListener('click', () => setCount(count + 1));

  const decrementButton = document.createElement('button');
  decrementButton.textContent = '−';
  decrementButton.className = 'bg-gray-400 hover:bg-gray-500 text-white w-10 h-10 rounded-full text-xl font-bold transition shadow';
  decrementButton.addEventListener('click', () => setCount(Math.max(0, count - 1)));

  const resetButton = document.createElement('button');
  resetButton.textContent = 'Reset';
  resetButton.className = 'bg-red-400 hover:bg-red-500 text-white px-4 py-1 rounded-full text-sm font-medium transition shadow';
  resetButton.addEventListener('click', () => setCount(0));

  btnGroup.appendChild(decrementButton);
  btnGroup.appendChild(incrementButton);
  btnGroup.appendChild(resetButton);
  widget.appendChild(btnGroup);
  updateCounter();

  // Live-ish uptime
  const startTime = Date.now();
  const uptimeEl = widget.querySelector('#uptime');
  setInterval(() => {
    const elapsed = Math.floor((Date.now() - startTime) / 1000);
    const mins = Math.floor(elapsed / 60);
    const secs = elapsed % 60;
    uptimeEl.textContent = `You've been here ${mins}m ${secs}s`;
  }, 1000);
}
