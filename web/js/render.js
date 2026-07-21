/**
 * 渲染模块：标签页、面板、数据卡片
 */

import { t } from './i18n.js';
import { esc, isSusfsCompat } from './utils.js';
import { SUSFS_COMPAT_MIN } from './config.js';
import { showModal } from './modal.js';

// ---- 标签页渲染 ----

export function renderTabs(datasets) {
  var tabsEl = document.getElementById('tabs');
  tabsEl.innerHTML = '';

  // 创建滑动指示器
  var indicator = document.createElement('div');
  indicator.className = 'tab-indicator';
  tabsEl.appendChild(indicator);

  datasets.forEach(function (ds, idx) {
    var btn = document.createElement('button');
    btn.className = 'tab';
    btn.textContent = ds.meta.label;
    btn.dataset.panel = 'panel-' + idx;
    btn.addEventListener('click', function () { activateTab(btn); });
    tabsEl.appendChild(btn);
  });
}

function activateTab(btn) {
  document.querySelectorAll('.tab').forEach(function (t) { t.classList.remove('active'); });
  document.querySelectorAll('.tab-panel').forEach(function (p) { p.classList.remove('active'); });
  btn.classList.add('active');
  var panel = document.getElementById(btn.dataset.panel);
  if (panel) panel.classList.add('active');
  moveIndicator(btn);
}

// 滑动指示器定位
function moveIndicator(tab) {
  var indicator = document.querySelector('.tab-indicator');
  if (!indicator || !tab) return;
  var padding = parseFloat(getComputedStyle(tab).paddingLeft) || 16;
  indicator.style.left = (tab.offsetLeft + padding) + 'px';
  indicator.style.width = (tab.offsetWidth - padding * 2) + 'px';
}

// ---- 面板渲染 ----

export function renderPanels(datasets) {
  var content = document.getElementById('content');
  content.innerHTML = '';

  datasets.forEach(function (ds, idx) {
    var panel = document.createElement('div');
    panel.className = 'tab-panel';
    panel.id = 'panel-' + idx;
    panel.innerHTML = buildCard(ds.data, ds.meta);
    content.appendChild(panel);

    // 表格行交错入场延迟
    panel.querySelectorAll('tbody tr').forEach(function (tr, i) {
      tr.style.animationDelay = (i * 20) + 'ms';
    });
  });
}

// ---- 构建数据卡片 HTML ----

function buildCard(data, meta) {
  var entries = data.entries || [];
  var lts = data.lts;
  var depCutoff = data.deprecated_cutoff || data.deprecatedCutoff || meta.deprecatedCutoff || '';
  var hasDepCutoff = typeof depCutoff === 'string' && depCutoff.length > 0;
  var totalReleases = entries.length;
  var firstDate = entries.length > 0 ? entries[0].date : 'N/A';
  var lastDate = entries.length > 0 ? entries[entries.length - 1].date : 'N/A';
  var lastKernel = entries.length > 0 ? entries[entries.length - 1].kernel : 'N/A';

  // LTS 信息
  var ltsHtml = '';
  if (lts) {
    var ltsSublevel = lts.split('.')[2] || '';
    ltsHtml =
      '<div class="lts-box lts-clickable" data-android="' + esc(meta.android) + '" data-kernel="' + esc(meta.kernel) + '" data-sublevel="' + esc(ltsSublevel) + '" data-patch="lts">' +
        '<span class="lts-label">LTS</span>' +
        '<span class="lts-version">' + esc(lts) + '</span>' +
      '</div>';
  }

  // 弃用标记
  var depBadge = hasDepCutoff
    ? '<span class="badge badge-deprecated" title="' + esc(t.deprecatedInfo) + '">' + esc(t.deprecated) + ' \u2264 ' + esc(depCutoff) + '</span>'
    : '';

  // SUSFS 兼容标记
  var hasSusfs = entries.some(function (e) { return isSusfsCompat(e.kernel); });
  var susfsMinKernel = hasSusfs ? meta.kernel + '.' + SUSFS_COMPAT_MIN[meta.kernel] : '';
  var susfsBadgeHeader = hasSusfs
    ? '<a href="https://gitlab.com/simonpunk/susfs4ksu" target="_blank" rel="noopener noreferrer" class="badge badge-susfs-header" title="' + esc(t.susfsCompatInfo) + '">' + esc(t.susfsCompat) + ' \u2265 ' + esc(susfsMinKernel) + '</a>'
    : '';

  // 图例条
  var legendItems = '';
  if (hasDepCutoff) {
    legendItems += '<div class="legend-item legend-deprecated">' +
      '<span class="badge badge-deprecated">' + esc(t.deprecated) + '</span>' +
      '<span class="legend-text">' + esc(t.deprecatedInfo) + '</span>' +
    '</div>';
  }
  if (hasSusfs) {
    legendItems += '<div class="legend-item legend-susfs">' +
      '<span class="badge-susfs">' + esc(t.susfsCompat) + '</span>' +
      '<span class="legend-text">' + esc(t.susfsCompatInfo) + '</span>' +
    '</div>';
  }
  var legendHtml = legendItems ? '<div class="legend-strip">' + legendItems + '</div>' : '';

  // 双列表格（从旧到新排列）
  var mid = Math.ceil(entries.length / 2);
  var leftCol = entries.slice(0, mid);
  var rightCol = entries.slice(mid);

  function buildHalf(col, isRight) {
    var rows = '';
    col.forEach(function (entry, i) {
      var sublevel = entry.kernel.split('.')[2] || '';
      var isDeprecated = hasDepCutoff && entry.date <= depCutoff;
      var isLatest = isRight ? (i === col.length - 1) : (rightCol.length === 0 && i === col.length - 1);
      var rowClass = 'row-clickable';
      if (isDeprecated) rowClass += ' row-deprecated';
      var depBadgeInner = isDeprecated ? '<span class="badge badge-deprecated" title="' + esc(t.deprecatedInfo) + '">' + esc(t.deprecated) + '</span>' : '';
      var newBadge = isLatest ? '<span class="badge-new">' + esc(t.newBadge) + '</span>' : '';
      var susfsBadge = isSusfsCompat(entry.kernel) ? '<a href="https://gitlab.com/simonpunk/susfs4ksu" target="_blank" rel="noopener noreferrer" class="badge-susfs" title="SUSFS patches work directly" onclick="event.stopPropagation();">' + esc(t.susfsCompat) + '</a>' : '';
      var badges = depBadgeInner + susfsBadge + newBadge;
      var badgesHtml = badges ? '<span class="kv-badges">' + badges + '</span>' : '';
      rows += '<tr class="' + rowClass + '" data-android="' + esc(meta.android) + '" data-kernel="' + esc(meta.kernel) + '" data-sublevel="' + esc(sublevel) + '" data-patch="' + esc(entry.date) + '">' +
        '<td class="date-cell">' + esc(entry.date) + '</td>' +
        '<td class="kernel-version"><span class="kv-text">' + esc(entry.kernel) + '</span>' + badgesHtml + '</td>' +
      '</tr>';
    });
    return '<table>' +
      '<thead class="table-half-head"><tr><th>' + t.date + '</th><th>' + t.kernelVersion + '</th></tr></thead>' +
      '<tbody>' + rows + '</tbody>' +
    '</table>';
  }

  return '<div class="card">' +
      '<div class="card-header">' +
        '<span class="badge badge-android">' + esc(meta.android) + '</span>' +
        '<span class="badge badge-kernel">Kernel ' + esc(meta.kernel) + '</span>' +
        depBadge +
        susfsBadgeHeader +
      '</div>' +
      legendHtml +
      ltsHtml +
      '<div class="stats">' +
        '<div class="stat"><div class="stat-label">' + t.releases + '</div><div class="stat-value">' + totalReleases + '</div></div>' +
        '<div class="stat"><div class="stat-label">' + t.first + '</div><div class="stat-value">' + esc(firstDate) + '</div></div>' +
        '<div class="stat"><div class="stat-label">' + t.latest + '</div><div class="stat-value">' + esc(lastDate) + '</div></div>' +
        '<div class="stat"><div class="stat-label">' + t.latestKernel + '</div><div class="stat-value">' + esc(lastKernel) + '</div></div>' +
      '</div>' +
      '<div class="table-dual-wrapper">' +
        '<div class="table-dual-header">' +
          '<span>' + t.date + '</span>' +
          '<span>' + t.kernelVersion + '</span>' +
        '</div>' +
        '<div class="table-dual-body">' +
          '<div class="table-half">' + buildHalf(leftCol, false) + '</div>' +
          '<div class="table-half">' + buildHalf(rightCol, true) + '</div>' +
        '</div>' +
      '</div>' +
    '</div>';
}

// ---- 统计数字计数动画 ----

export function animateCounters(panel) {
  panel.querySelectorAll('.stat-value').forEach(function (el) {
    var text = el.textContent.trim();
    // 仅对纯整数值执行计数动画，跳过日期和内核版本
    if (!/^\d+$/.test(text)) return;
    var target = parseInt(text, 10);
    if (target <= 0) return;

    var start = 0;
    var duration = 600;
    var startTime = null;

    function step(ts) {
      if (!startTime) startTime = ts;
      var progress = Math.min((ts - startTime) / duration, 1);
      var ease = 1 - Math.pow(1 - progress, 3);
      el.textContent = Math.round(start + (target - start) * ease);
      if (progress < 1) requestAnimationFrame(step);
    }

    el.textContent = '0';
    requestAnimationFrame(step);
  });
}

// ---- 行点击涟漪效果 ----
// 注意：<tr> 不支持 position:relative 和 overflow:hidden，
// 因此将涟漪 span 挂载到被点击的 <td> 上

export function initRipple() {
  document.addEventListener('click', function (e) {
    var row = e.target.closest('tr.row-clickable');
    if (!row) return;

    var td = e.target.closest('td');
    if (!td) return;

    var rect = td.getBoundingClientRect();
    var size = Math.max(rect.width, rect.height);
    var ripple = document.createElement('span');
    ripple.className = 'row-ripple';
    ripple.style.width = ripple.style.height = size + 'px';
    ripple.style.left = (e.clientX - rect.left - size / 2) + 'px';
    ripple.style.top = (e.clientY - rect.top - size / 2) + 'px';
    td.appendChild(ripple);

    ripple.addEventListener('animationend', function () { ripple.remove(); });
  });
}
