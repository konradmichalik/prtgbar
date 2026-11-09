const root = document.documentElement;

function currentTheme() {
  if (root.dataset.theme) return root.dataset.theme;
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function setupThemeToggle() {
  const toggle = document.querySelector('.theme-toggle');
  if (!toggle) return;
  const label = () => (currentTheme() === 'dark' ? 'Switch to light mode' : 'Switch to dark mode');
  toggle.setAttribute('aria-label', label());
  toggle.addEventListener('click', () => {
    const next = currentTheme() === 'dark' ? 'light' : 'dark';
    root.dataset.theme = next;
    toggle.setAttribute('aria-label', label());
    try {
      localStorage.setItem('prtgbar-theme', next);
    } catch {
      // Storage can be blocked; the theme then only lasts for this page view.
    }
  });
}

function setupCopyButtons() {
  const status = document.getElementById('copy-status');
  document.querySelectorAll('.code-copy').forEach((button) => {
    button.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(button.dataset.copy);
      } catch {
        return;
      }
      button.classList.add('copied');
      if (status) status.textContent = 'Command copied';
      setTimeout(() => button.classList.remove('copied'), 2000);
    });
  });
}

function setupTabs() {
  const tabs = [...document.querySelectorAll('[role="tab"]')];
  const select = (tab) => {
    tabs.forEach((other) => {
      const selected = other === tab;
      other.setAttribute('aria-selected', String(selected));
      other.tabIndex = selected ? 0 : -1;
      document.getElementById(other.getAttribute('aria-controls')).hidden = !selected;
    });
    tab.focus();
  };
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => select(tab));
    tab.addEventListener('keydown', (event) => {
      const step = { ArrowRight: 1, ArrowLeft: -1 }[event.key];
      if (!step) return;
      event.preventDefault();
      select(tabs[(index + step + tabs.length) % tabs.length]);
    });
  });
}

setupThemeToggle();
setupCopyButtons();
setupTabs();
