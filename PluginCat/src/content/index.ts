import { initApiObserver, initNetworkObserver } from './observe';
import { mountPet } from './pet';

// 尽早启动观察：
// - initNetworkObserver：PerformanceObserver，收 resource timing（URL/耗时/状态）
// - initApiObserver：接收 MAIN world 注入脚本回传的 fetch/XHR 明细（含响应体摘要）
initNetworkObserver();
initApiObserver();

if (window.top === window) {
  const boot = () => {
    mountPet();
    console.log('[web-pet] content script mounted on', location.href);
  };
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot, { once: true });
  } else {
    boot();
  }
}
