import { initNetworkObserver } from './observe';
import { mountPet } from './pet';

// 尽早启动网络观察，以便能捕获用户真正发起的请求
initNetworkObserver();

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
