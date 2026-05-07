import { defineManifest } from '@crxjs/vite-plugin';

export default defineManifest({
  manifest_version: 3,
  name: '网页电子宠物',
  description: '一只陪你逛网页的电子宠物：能读懂当前页面并自动化操作（滚动/点击/填写/查看网络请求），支持 Hunyuan / GLM / DeepSeek / OpenAI。',
  version: '0.1.0',
  action: {
    default_title: '打开设置',
    default_icon: {
      16: 'icons/icon-16.png',
      32: 'icons/icon-32.png'
    }
  },
  icons: {
    16: 'icons/icon-16.png',
    32: 'icons/icon-32.png',
    48: 'icons/icon-48.png',
    128: 'icons/icon-128.png'
  },
  options_page: 'src/options/index.html',
  background: {
    service_worker: 'src/background/index.ts',
    type: 'module'
  },
  content_scripts: [
    {
      matches: ['<all_urls>'],
      js: ['src/content/index.ts'],
      run_at: 'document_idle',
      all_frames: false
    }
  ],
  permissions: ['storage', 'activeTab', 'scripting'],
  host_permissions: [
    'https://api.hunyuan.cloud.tencent.com/*',
    'https://open.bigmodel.cn/*',
    'https://api.deepseek.com/*',
    'https://api.openai.com/*'
  ],
  web_accessible_resources: [
    {
      resources: ['src/content/pet.css'],
      matches: ['<all_urls>']
    }
  ]
});
