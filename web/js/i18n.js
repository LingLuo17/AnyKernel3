/**
 * 国际化模块：多语言文本 + 语言切换
 */

const I18N = {
  en: {
    title: 'GKI Kernel Versions',
    subtitle: 'Android Generic Kernel Image \u2014 version tracking dashboard',
    light: 'Light',
    dark: 'Dark',
    loading: 'Loading kernel data\u2026',
    errorTitle: 'Failed to load kernel data.',
    errorHint: 'Make sure <code>web/data/</code> contains the JSON files.',
    releases: 'Releases',
    first: 'First',
    latest: 'Latest',
    latestKernel: 'Latest Kernel',
    date: 'Security Patch',
    kernelVersion: 'Kernel Version',
    deprecated: 'Deprecated',
    deprecatedInfo: 'No longer receives security patch merges',
    susfsCompatInfo: 'SUSFS patches work directly after installing KSU, no extra patching needed',
    footerPre: 'Data sourced from',
    footerPost: '. Updated automatically via GitHub Actions.',
    announce: 'Announcement',
    announceClose: 'Close',
    announceDismiss: 'Don\u2019t show today',
    modalTitle: 'GitHub Action Parameters',
    modalAndroid: 'Android Version',
    modalKernel: 'Kernel Version',
    modalSublevel: 'Sublevel',
    modalPatch: 'Security Patch Level',
    modalSectionSource: 'Source Code',
    modalRepoInit: 'Repo Init',
    modalSectionSusfs: 'SUSFS Patch',
    modalSusfsClone: 'Clone',
    copy: 'Copy',
    copied: 'Copied',
    tcTitle: 'Time Converter',
    tcDate: 'Date',
    tcTime: 'Time (UTC)',
    tcToast: 'Copied to clipboard',
    langSwitch: '\u4e2d\u6587',
    searchPlaceholder: 'Search date or kernel version\u2026',
    noResults: 'No matching results',
    newBadge: 'NEW',
    susfsCompat: 'SUSFS',
    guide: 'Guide',
  },
  zh: {
    title: 'GKI \u5185\u6838\u7248\u672c',
    subtitle: 'Android \u901a\u7528\u5185\u6838\u955c\u50cf \u2014 \u7248\u672c\u8ddf\u8e2a\u770b\u677f',
    light: '\u6d45\u8272',
    dark: '\u6df1\u8272',
    loading: '\u6b63\u5728\u52a0\u8f7d\u5185\u6838\u6570\u636e\u2026',
    errorTitle: '\u52a0\u8f7d\u5185\u6838\u6570\u636e\u5931\u8d25\u3002',
    errorHint: '\u8bf7\u786e\u4fdd <code>web/data/</code> \u5305\u542b JSON \u6587\u4ef6\u3002',
    releases: '\u53d1\u5e03\u6570',
    first: '\u8d77\u59cb',
    latest: '\u6700\u65b0',
    latestKernel: '\u6700\u65b0\u5185\u6838',
    date: '\u5b89\u5168\u8865\u4e01\u65e5\u671f',
    kernelVersion: '\u5185\u6838\u7248\u672c',
    deprecated: '\u5df2\u5f03\u7528',
    deprecatedInfo: '\u4e0d\u518d\u63a5\u53d7\u5b89\u5168\u8865\u4e01\u7684\u5408\u5e76',
    susfsCompatInfo: '\u5b89\u88c5 KSU \u540e\u53ef\u76f4\u63a5\u4f7f\u7528 SUSFS \u8865\u4e01\uff0c\u65e0\u9700\u4e8c\u6b21\u4fee\u590d',
    footerPre: '\u6570\u636e\u6765\u6e90\u4e8e',
    footerPost: '\u3002\u901a\u8fc7 GitHub Actions \u81ea\u52a8\u66f4\u65b0\u3002',
    announce: '\u516c\u544a',
    announceClose: '\u5173\u95ed',
    announceDismiss: '\u4eca\u65e5\u4e0d\u518d\u663e\u793a',
    modalTitle: 'GitHub Action \u53c2\u6570',
    modalAndroid: 'Android \u7248\u672c',
    modalKernel: '\u5185\u6838\u7248\u672c',
    modalSublevel: '\u5b50\u7248\u672c\u53f7',
    modalPatch: '\u5b89\u5168\u8865\u4e01\u7ea7\u522b',
    modalSectionSource: '\u6e90\u7801\u62c9\u53d6',
    modalRepoInit: 'Repo \u521d\u59cb\u5316',
    modalSectionSusfs: 'SUSFS \u8865\u4e01\u62c9\u53d6',
    modalSusfsClone: '\u514b\u9686',
    copy: '\u590d\u5236',
    copied: '\u5df2\u590d\u5236',
    tcTitle: '\u65f6\u95f4\u8f6c\u6362',
    tcDate: '\u65e5\u671f',
    tcTime: '\u65f6\u95f4 (UTC)',
    tcToast: '\u5df2\u590d\u5236\u5230\u526a\u8d34\u677f',
    langSwitch: 'EN',
    searchPlaceholder: '\u641c\u7d22\u65e5\u671f\u6216\u5185\u6838\u7248\u672c\u2026',
    noResults: '\u65e0\u5339\u914d\u7ed3\u679c',
    newBadge: '\u6700\u65b0',
    susfsCompat: 'SUSFS\u517c\u5bb9',
    guide: '教程',
  },
};

// 语言优先级：localStorage > navigator.language
var savedLang = localStorage.getItem('lang');
export var lang = savedLang || (/^zh\b/i.test(navigator.language) ? 'zh' : 'en');
export var t = I18N[lang];

/**
 * 初始化 i18n：设置页面语言属性、静态文本、语言切换按钮
 */
export function initI18n() {
  document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';

  // 设置静态元素文本
  document.getElementById('headerTitle').textContent = t.title;
  document.getElementById('headerSubtitle').textContent = t.subtitle;
  document.getElementById('loadingText').textContent = t.loading;
  document.getElementById('footerPre').textContent = t.footerPre;
  document.getElementById('footerPost').textContent = t.footerPost;
  document.getElementById('tcTitle').textContent = t.tcTitle;
  document.getElementById('tcDateLabel').textContent = t.tcDate;
  document.getElementById('tcTimeLabel').textContent = t.tcTime;
  document.getElementById('tcCopy').textContent = t.copy;
  document.getElementById('guideLabel').textContent = t.guide;
  document.title = t.title;

  // 语言切换按钮
  var langToggle = document.getElementById('langToggle');
  var langLabel = document.getElementById('langLabel');
  langLabel.textContent = t.langSwitch;

  langToggle.addEventListener('click', function () {
    var newLang = lang === 'zh' ? 'en' : 'zh';
    localStorage.setItem('lang', newLang);
    location.reload();
  });
}
