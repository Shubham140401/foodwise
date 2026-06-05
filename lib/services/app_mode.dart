// Shared constants for recommendation engine mode.
const kRecModeKey = 'rec_mode';
const kRecModeAi = 'ai';
const kRecModeStatic = 'static';

// LLM provider identifiers — stored in SharedPreferences under kLlmProviderKey.
const kLlmProviderKey = 'llm_provider';
const kProviderClaude = 'claude';
const kProviderOpenAI = 'openai';
const kProviderGemini = 'gemini';
const kProviderDeepSeek = 'deepseek';
const kProviderOpenRouter = 'openrouter';

const kAllProviders = [
  kProviderClaude,
  kProviderOpenAI,
  kProviderGemini,
  kProviderDeepSeek,
  kProviderOpenRouter,
];

// Human-readable labels for each provider.
const kProviderLabels = {
  kProviderClaude: 'Claude (Anthropic)',
  kProviderOpenAI: 'OpenAI',
  kProviderGemini: 'Gemini (Google)',
  kProviderDeepSeek: 'DeepSeek',
  kProviderOpenRouter: 'OpenRouter',
};

// Placeholder hint for the API key field per provider.
const kProviderKeyHints = {
  kProviderClaude: 'sk-ant-...',
  kProviderOpenAI: 'sk-...',
  kProviderGemini: 'AIza...',
  kProviderDeepSeek: 'sk-...',
  kProviderOpenRouter: 'sk-or-...',
};
