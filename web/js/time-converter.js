/**
 * 时间转换器模块
 */

import { t } from './i18n.js';

export function initTimeConverter() {
  var tcDate = document.getElementById('tcDate');
  var tcTime = document.getElementById('tcTime');
  var tcResult = document.getElementById('tcResult');
  var tcCopy = document.getElementById('tcCopy');

  // 默认填入当前 UTC 时间
  var now = new Date();
  tcDate.value = now.toISOString().slice(0, 10);
  tcTime.value = now.toISOString().slice(11, 19);
  updateTC();

  function updateTC() {
    var d = tcDate.value;
    var tm = tcTime.value;
    if (!d || !tm) { tcResult.textContent = '\u2014'; tcCopy.dataset.copy = ''; return; }
    var parts = tm.split(':');
    var h = parseInt(parts[0], 10);
    var m = parseInt(parts[1], 10);
    var s = parseInt(parts[2] || '0', 10);
    var dp = d.split('-');
    var local = new Date(Date.UTC(parseInt(dp[0]), parseInt(dp[1]) - 1, parseInt(dp[2]), h, m, s));
    var days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    var months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    var pad = function (n) { return String(n).padStart(2, '0'); };
    var utcStr = days[local.getUTCDay()] + ' ' + months[local.getUTCMonth()] + ' ' + pad(local.getUTCDate()) + ' ' + pad(local.getUTCHours()) + ':' + pad(local.getUTCMinutes()) + ':' + pad(local.getUTCSeconds()) + ' UTC ' + local.getUTCFullYear();
    tcResult.textContent = utcStr;
    tcCopy.dataset.copy = utcStr;
  }

  tcDate.addEventListener('input', updateTC);
  tcTime.addEventListener('input', updateTC);
}
