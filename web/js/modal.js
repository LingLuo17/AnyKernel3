/**
 * 详情弹窗模块（点击内核版本行弹出 GitHub Action 参数）
 */

import { t } from './i18n.js';
import { esc } from './utils.js';

var modal = document.getElementById('modal');
var modalTitle = document.getElementById('modalTitle');
var modalBody = document.getElementById('modalBody');
var modalClose = document.getElementById('modalClose');

// 生成弹窗中的一行（普通文本或代码块）
function modalRow(label, value, isCode) {
  if (isCode) {
    return '<div class="modal-row modal-row-code">' +
        '<span class="modal-label">' + label + '</span>' +
        '<div class="modal-code-wrapper">' +
          '<code class="modal-code">' + esc(value) + '</code>' +
          '<button class="modal-copy" data-copy="' + esc(value) + '">' + t.copy + '</button>' +
        '</div>' +
      '</div>';
  }
  return '<div class="modal-row">' +
      '<span class="modal-label">' + label + '</span>' +
      '<span class="modal-value-group">' +
        '<span class="modal-value">' + esc(value) + '</span>' +
        '<button class="modal-copy" data-copy="' + esc(value) + '">' + t.copy + '</button>' +
      '</span>' +
    '</div>';
}

// 显示详情弹窗
export function showModal(android, kernel, sublevel, patch) {
  modalTitle.textContent = t.modalTitle;

  var formattedBranch = android + '-' + kernel + '-' + patch;
  var repoInitCmd = 'repo init --depth=1 -u https://android.googlesource.com/kernel/manifest -b common-' + formattedBranch + ' --repo-rev=v2.16';

  var susfsBranch = 'gki-' + android + '-' + kernel;
  var susfsCloneCmd = 'git clone https://gitlab.com/simonpunk/susfs4ksu.git -b ' + susfsBranch;

  modalBody.innerHTML =
    modalRow(t.modalAndroid, android) +
    modalRow(t.modalKernel, kernel) +
    modalRow(t.modalSublevel, sublevel) +
    modalRow(t.modalPatch, patch) +
    '<div class="modal-section">' + esc(t.modalSectionSource) + '</div>' +
    modalRow(t.modalRepoInit, repoInitCmd, true) +
    '<div class="modal-section">' + esc(t.modalSectionSusfs) + '</div>' +
    modalRow(t.modalSusfsClone, susfsCloneCmd, true);
  modal.style.display = '';
}

export function hideModal() {
  modal.style.display = 'none';
}

// 初始化弹窗事件监听
export function initModal() {
  modalClose.addEventListener('click', hideModal);
  modal.addEventListener('click', function (e) {
    if (e.target === modal) hideModal();
  });

  // 点击表格行或 LTS 框打开弹窗（事件委托）
  document.addEventListener('click', function (e) {
    // LTS 框
    var ltsBox = e.target.closest('.lts-clickable');
    if (ltsBox) {
      showModal(
        ltsBox.dataset.android,
        ltsBox.dataset.kernel,
        ltsBox.dataset.sublevel,
        ltsBox.dataset.patch
      );
      return;
    }
    // 表格行
    var row = e.target.closest('.row-clickable');
    if (!row) return;
    showModal(row.dataset.android, row.dataset.kernel, row.dataset.sublevel, row.dataset.patch);
  });
}
