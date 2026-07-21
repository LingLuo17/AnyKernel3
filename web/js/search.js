/**
 * 搜索过滤模块
 */

import { t } from './i18n.js';

export function initSearch() {
  var searchToggle = document.getElementById('searchToggle');
  var searchInput = document.getElementById('searchInput');
  searchInput.placeholder = t.searchPlaceholder;

  // 搜索框展开/收起
  searchToggle.addEventListener('click', function () {
    var isOpen = searchInput.classList.toggle('open');
    if (isOpen) {
      searchInput.style.display = '';
      searchInput.focus();
    } else {
      searchInput.value = '';
      searchInput.style.display = 'none';
      filterActivePanel('');
    }
  });

  // 输入时实时过滤
  searchInput.addEventListener('input', function () {
    filterActivePanel(searchInput.value);
  });
}

// 过滤当前激活面板中的表格行
function filterActivePanel(rawQuery) {
  var panel = document.querySelector('.tab-panel.active');
  if (!panel) return;
  var card = panel.querySelector('.card');
  if (!card) return;

  var query = rawQuery.trim().toLowerCase();
  var wrapper = card.querySelector('.table-dual-wrapper');
  var rows = wrapper.querySelectorAll('tbody tr');
  var visibleCount = 0;

  rows.forEach(function (row) {
    if (!query) { row.style.display = ''; visibleCount++; return; }
    var dateText = (row.querySelector('.date-cell') || {}).textContent || '';
    var kernelText = (row.querySelector('.kernel-version') || {}).textContent || '';
    var match = dateText.toLowerCase().indexOf(query) !== -1 || kernelText.toLowerCase().indexOf(query) !== -1;
    row.style.display = match ? '' : 'none';
    if (match) visibleCount++;
  });

  var existing = card.querySelector('.search-no-results');
  if (visibleCount === 0 && query) {
    if (!existing) {
      var msg = document.createElement('div');
      msg.className = 'search-no-results';
      msg.textContent = t.noResults;
      wrapper.parentNode.insertBefore(msg, wrapper.nextSibling);
    }
    wrapper.style.display = 'none';
  } else {
    if (existing) existing.remove();
    wrapper.style.display = '';
  }
}
