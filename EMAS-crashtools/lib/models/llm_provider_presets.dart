/// 常见 OpenAI 兼容大模型服务商预设（Base URL + Chat 路径 + 默认模型名）。
class LlmProviderPreset {
  const LlmProviderPreset({
    required this.id,
    required this.label,
    required this.baseUrl,
    this.chatPath = 'v1/chat/completions',
    this.defaultModel = '',
    this.description = '',
  });

  final String id;
  final String label;
  final String baseUrl;
  /// 相对 Base URL 的路径片段（无前导 `/`），如 `v1/chat/completions` 或 `chat/completions`。
  final String chatPath;
  final String defaultModel;
  final String description;

  static const String customId = 'custom';

  static final List<LlmProviderPreset> all = [
    const LlmProviderPreset(
      id: customId,
      label: '自定义',
      baseUrl: '',
      chatPath: 'v1/chat/completions',
      defaultModel: '',
      description: '自行填写 Base URL；可在下方修改路径与模型。',
    ),
    const LlmProviderPreset(
      id: 'openai',
      label: 'OpenAI',
      baseUrl: 'https://api.openai.com',
      defaultModel: 'gpt-4o-mini',
      description: '官方 api.openai.com',
    ),
    const LlmProviderPreset(
      id: 'deepseek',
      label: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      defaultModel: 'deepseek-chat',
    ),
    const LlmProviderPreset(
      id: 'zhipu',
      label: '智谱 GLM',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      chatPath: 'chat/completions',
      defaultModel: 'glm-4.6v',
      description: 'BigModel 兼容接口；Base 须为 …/api/paas/v4（勿只写到 /paas），路径为 chat/completions。',
    ),
    const LlmProviderPreset(
      id: 'dashscope',
      label: '阿里云 通义 (DashScope 兼容模式)',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode',
      defaultModel: 'qwen-plus',
      description: '需 DashScope API-Key；模型名以控制台为准。',
    ),
    const LlmProviderPreset(
      id: 'moonshot',
      label: '月之暗面 Kimi',
      baseUrl: 'https://api.moonshot.cn',
      defaultModel: 'moonshot-v1-8k',
    ),
    const LlmProviderPreset(
      id: 'doubao',
      label: '火山引擎 豆包 (方舟 OpenAI 兼容)',
      baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      chatPath: 'chat/completions',
      defaultModel: '',
      description: '模型名需填控制台中的 Endpoint 模型 ID；地域以你开通为准，可改 Base URL。',
    ),
    const LlmProviderPreset(
      id: 'groq',
      label: 'Groq',
      baseUrl: 'https://api.groq.com/openai',
      defaultModel: 'llama-3.3-70b-versatile',
    ),
    const LlmProviderPreset(
      id: 'openrouter',
      label: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      chatPath: 'chat/completions',
      defaultModel: 'openai/gpt-4o-mini',
    ),
    const LlmProviderPreset(
      id: 'siliconflow',
      label: '硅基流动 SiliconFlow',
      baseUrl: 'https://api.siliconflow.cn',
      defaultModel: 'Qwen/Qwen2.5-7B-Instruct',
    ),
    const LlmProviderPreset(
      id: 'amazon_gateway',
      label: 'Amazon / 其它兼容网关',
      baseUrl: '',
      defaultModel: '',
      description: 'Bedrock 原生为 AWS 签名，本客户端仅支持 Bearer。请填写你已部署的 OpenAI 兼容代理地址。',
    ),
  ];

  static LlmProviderPreset? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}
