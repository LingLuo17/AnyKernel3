/**
 * 通用工具函数
 */

import { RUNTIME_CACHE_KEY, SUSFS_COMPAT_MIN } from './config.js';

// HTML 转义，防止 XSS
export function esc(str) {
  var el = document.createElement('span');
  el.textContent = str;
  return el.innerHTML;
}

// 复制文本到剪贴板（兼容旧浏览器）
export function copyText(text) {
  if (navigator.clipboard && navigator.clipboard.writeText) {
    return navigator.clipboard.writeText(text);
  }
  var ta = document.createElement('textarea');
  ta.value = text;
  ta.style.position = 'fixed';
  ta.style.opacity = '0';
  document.body.appendChild(ta);
  ta.select();
  document.execCommand('copy');
  document.body.removeChild(ta);
  return Promise.resolve();
}

// 给 URL 追加缓存破坏参数
export function withCacheKey(url) {
  return url + (url.indexOf('?') === -1 ? '?' : '&') + 'v=' + encodeURIComponent(RUNTIME_CACHE_KEY);
}

// 强制无缓存请求 JSON
export async function fetchJsonFresh(url) {
  var r = await fetch(withCacheKey(url), { cache: 'no-store' });
  if (!r.ok) throw new Error('HTTP ' + r.status);
  return r.json();
}

// 判断内核版本是否兼容 SUSFS
export function isSusfsCompat(kernelStr) {
  var parts = kernelStr.split('.');
  var major = parts[0] + '.' + parts[1];
  var min = SUSFS_COMPAT_MIN[major];
  if (min == null) return false;
  var sublevel = parseInt(parts[2], 10);
  return sublevel >= min;
}
