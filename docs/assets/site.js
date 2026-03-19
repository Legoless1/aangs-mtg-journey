(() => {
  'use strict';
  const button = document.getElementById('theme');
  const prefersDark = () => window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
  const nextTheme = (value) => value === 'light' ? 'dark' : value === 'dark' ? 'auto' : 'light';
  const applyTheme = (value) => {
    const pref = ['light', 'dark', 'auto'].includes(value) ? value : 'auto';
    localStorage.setItem('portable-blog-theme', pref);
    const effective = pref === 'auto' ? (prefersDark() ? 'dark' : 'light') : pref;
    document.documentElement.setAttribute('data-theme', effective);
    if (button) {
      button.textContent = `Theme: ${pref.charAt(0).toUpperCase()}${pref.slice(1)}`;
      button.dataset.next = nextTheme(pref);
    }
  };
  document.addEventListener('DOMContentLoaded', () => {
    applyTheme(localStorage.getItem('portable-blog-theme') || 'auto');
    if (button) {
      button.addEventListener('click', () => applyTheme(button.dataset.next || 'auto'));
    }
    if (window.matchMedia) {
      window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
        if ((localStorage.getItem('portable-blog-theme') || 'auto') === 'auto') {
          applyTheme('auto');
        }
      });
    }
    const root = document.getElementById('cusdis_thread');
    if (!root) return;
    const mount = () => {
      if (window.CUSDIS && typeof window.CUSDIS.initial === 'function') {
        root.innerHTML = '';
        window.CUSDIS.initial();
      }
    };
    const existing = document.querySelector('script[data-cusdis-script="1"]');
    if (existing) {
      if (existing.dataset.loaded === '1') {
        mount();
        return;
      }
      existing.addEventListener('load', mount, { once: true });
      return;
    }
    const script = document.createElement('script');
    script.async = true;
    script.defer = true;
    script.src = root.dataset.scriptSrc;
    script.dataset.cusdisScript = '1';
    script.addEventListener('load', () => {
      script.dataset.loaded = '1';
      mount();
    }, { once: true });
    root.closest('.comments')?.insertAdjacentHTML('beforeend', '');
    document.body.appendChild(script);
  });
})();