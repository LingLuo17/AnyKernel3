/**
 * 公告弹窗模块（含简易 Markdown 渲染）
 */

import { t, lang } from './i18n.js';
import { esc, fetchJsonFresh } from './utils.js';

var announceModal = document.getElementById('announceModal');
var announceModalTitle = document.getElementById('announceModalTitle');
var announceModalBody = document.getElementById('announceModalBody');
var announceModalClose = document.getElementById('announceModalClose');
var announceDismissToday = document.getElementById('announceDismissToday');
var announceCloseBtn = document.getElementById('announceClose');

// 获取当前本地日期字符串
function localDateStr() {
  var d = new Date();
  return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
}

export function hideAnnounce() {
  announceModal.style.display = 'none';
}

function dismissAnnounceToday() {
  localStorage.setItem('announce_dismiss', localDateStr());
  hideAnnounce();
}

// ---- 简易 Markdown 渲染 ----

// 渲染行内 Markdown（代码、链接、加粗、斜体）
function renderInlineMarkdown(text) {
  var html = esc(text == null ? '' : String(text));
  var codeTokens = [];

  html = html.replace(/`([^`\n]+)`/g, function (_, codeText) {
    codeTokens.push('<code>' + codeText + '</code>');
    return '\u0000CODE' + (codeTokens.length - 1) + '\u0000';
  });

  html = html.replace(/\[([^\]\n]+)\]\(([^)\s]+)\)/g, function (_, label, url) {
    return '<a href="' + url + '" target="_blank" rel="noopener noreferrer">' + label + '</a>';
  });
  html = html.replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>');
  html = html.replace(/\*([^*\n]+)\*/g, '<em>$1</em>');

  return html.replace(/\u0000CODE(\d+)\u0000/g, function (_, idx) {
    return codeTokens[Number(idx)] || '';
  });
}

// 渲染块级 Markdown（标题、列表、引用、代码块、段落）
function renderMarkdown(markdownText) {
  var normalized = String(markdownText == null ? '' : markdownText)
    .replace(/\r\n?/g, '\n')
    .trim();
  if (!normalized) return '';

  var blocks = normalized.split(/\n{2,}/);
  var out = [];

  blocks.forEach(function (block) {
    var lines = block.split('\n');
    var fence = block.match(/^```([a-zA-Z0-9_-]+)?\n([\s\S]*?)\n```$/);
    if (fence) {
      var langClass = fence[1] ? ' class="lang-' + fence[1].toLowerCase() + '"' : '';
      out.push('<pre><code' + langClass + '>' + esc(fence[2]) + '</code></pre>');
      return;
    }

    var heading = block.match(/^\s*(#{1,6})\s+(.+)$/);
    if (heading && lines.length === 1) {
      var level = heading[1].length;
      out.push('<h' + level + '>' + renderInlineMarkdown(heading[2]) + '</h' + level + '>');
      return;
    }

    if (lines.every(function (line) { return /^\s*[-*]\s+/.test(line); })) {
      out.push('<ul>' + lines.map(function (line) {
        return '<li>' + renderInlineMarkdown(line.replace(/^\s*[-*]\s+/, '')) + '</li>';
      }).join('') + '</ul>');
      return;
    }

    if (lines.every(function (line) { return /^\s*\d+\.\s+/.test(line); })) {
      out.push('<ol>' + lines.map(function (line) {
        return '<li>' + renderInlineMarkdown(line.replace(/^\s*\d+\.\s+/, '')) + '</li>';
      }).join('') + '</ol>');
      return;
    }

    if (lines.every(function (line) { return /^\s*>\s?/.test(line); })) {
      out.push('<blockquote>' + lines.map(function (line) {
        return renderInlineMarkdown(line.replace(/^\s*>\s?/, ''));
      }).join('<br>') + '</blockquote>');
      return;
    }

    out.push('<p>' + lines.map(renderInlineMarkdown).join('<br>') + '</p>');
  });

  return out.join('');
}

// 标准化公告文本
function normalizeAnnouncementText(value) {
  if (Array.isArray(value)) return value.join('\n');
  if (value == null) return '';
  return String(value);
}

// 根据当前语言获取公告内容
function getAnnouncementText(item) {
  if (lang === 'zh') {
    return normalizeAnnouncementText(item.content_zh_md || item.content_zh || item.content_md || item.content);
  }
  return normalizeAnnouncementText(item.content_md || item.content || item.content_zh_md || item.content_zh);
}

// 初始化公告模块
export function initAnnouncement() {
  announceModalClose.addEventListener('click', hideAnnounce);
  announceCloseBtn.addEventListener('click', hideAnnounce);
  announceDismissToday.addEventListener('click', dismissAnnounceToday);
  announceModal.addEventListener('click', function (e) {
    if (e.target === announceModal) hideAnnounce();
  });

  // 加载公告数据
  loadAnnouncement();
}

async function loadAnnouncement() {
  try {
    var json = await fetchJsonFresh('data/announcement.json');
    var items = json.items;
    if (!items || items.length === 0) return;

    if (localStorage.getItem('announce_dismiss') === localDateStr()) return;

    announceModalTitle.textContent = t.announce;
    announceDismissToday.textContent = t.announceDismiss;
    announceCloseBtn.textContent = t.announceClose;

    var html = '';
    items.forEach(function (item) {
      var text = getAnnouncementText(item);
      var markdownHtml = renderMarkdown(text);
      if (!markdownHtml) return;

      var dateText = item.date ? esc(item.date) : '';
      html += '<article class="announce-item">' +
        '<div class="announce-text">' + markdownHtml + '</div>' +
        (dateText ? '<div class="announce-meta"><time class="announce-date" datetime="' + dateText + '">' + dateText + '</time></div>' : '') +
        '</article>';
    });
    if (!html) return;
    announceModalBody.innerHTML = html;
    announceModal.style.display = '';
  } catch (e) {
    // 静默忽略加载失败
  }
}
