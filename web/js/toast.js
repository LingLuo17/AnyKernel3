/**
 * Toast 提示模块
 */

var toastEl = document.getElementById('toast');
var toastTimer;

export function showToast(msg) {
  clearTimeout(toastTimer);
  toastEl.textContent = msg;
  toastEl.classList.add('show');
  toastTimer = setTimeout(function () {
    toastEl.classList.remove('show');
  }, 1800);
}
