/**
 * 主题切换模块（深色/浅色）
 */

import { t } from './i18n.js';

export function initTheme() {
  var themeToggle = document.getElementById('themeToggle');
  var themeIcon = document.getElementById('themeIcon');
  var themeLabel = document.getElementById('themeLabel');

  function setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('theme', theme);
    if (theme === 'dark') {
      themeIcon.textContent = '\u263D';
      themeLabel.textContent = t.light;
    } else {
      themeIcon.textContent = '\u2600';
      themeLabel.textContent = t.dark;
    }
  }

  var savedTheme = localStorage.getItem('theme') || 'dark';
  setTheme(savedTheme);

  themeToggle.addEventListener('click', function () {
    var current = document.documentElement.getAttribute('data-theme');
    setTheme(current === 'dark' ? 'light' : 'dark');
  });
}
