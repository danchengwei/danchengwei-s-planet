export type ProviderId = 'hunyuan' | 'glm' | 'deepseek' | 'openai';

export interface Provider {
  id: ProviderId;
  label: string;
  /** 完整的 chat completions 端点（OpenAI 兼容） */
  baseUrl: string;
  defaultModel: string;
  /** 获取 API Key 的文档/控制台链接 */
  docUrl: string;
  /** 默认 Key 前缀提示 */
  keyHint: string;
}

export const PROVIDERS: Record<ProviderId, Provider> = {
  hunyuan: {
    id: 'hunyuan',
    label: '腾讯混元 (Hunyuan)',
    baseUrl: 'https://api.hunyuan.cloud.tencent.com/v1/chat/completions',
    defaultModel: 'hunyuan-lite',
    docUrl: 'https://cloud.tencent.com/document/product/1729/111007',
    keyHint: 'sk-xxxxxx'
  },
  glm: {
    id: 'glm',
    label: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
    defaultModel: 'glm-4-flash',
    docUrl: 'https://open.bigmodel.cn/usercenter/apikeys',
    keyHint: 'xxxxxx.xxxxxx'
  },
  deepseek: {
    id: 'deepseek',
    label: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/chat/completions',
    defaultModel: 'deepseek-chat',
    docUrl: 'https://platform.deepseek.com/api_keys',
    keyHint: 'sk-xxxxxx'
  },
  openai: {
    id: 'openai',
    label: 'OpenAI (GPT)',
    baseUrl: 'https://api.openai.com/v1/chat/completions',
    defaultModel: 'gpt-4o-mini',
    docUrl: 'https://platform.openai.com/api-keys',
    keyHint: 'sk-xxxxxx'
  }
};

export const PROVIDER_IDS: ProviderId[] = ['hunyuan', 'glm', 'deepseek', 'openai'];
export const DEFAULT_PROVIDER: ProviderId = 'hunyuan';

export function getProvider(id: ProviderId): Provider {
  return PROVIDERS[id] || PROVIDERS[DEFAULT_PROVIDER];
}
