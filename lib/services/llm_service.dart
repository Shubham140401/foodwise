import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode.dart';

// Default model per provider. These are the fastest/cheapest capable models.
const _defaultModels = {
  kProviderClaude: 'claude-sonnet-4-20250514',
  kProviderOpenAI: 'gpt-4o-mini',
  kProviderGemini: 'gemini-1.5-flash',
  kProviderDeepSeek: 'deepseek-chat',
  kProviderOpenRouter: 'openai/gpt-4o-mini',
};

const _storage = FlutterSecureStorage();

class LlmService {
  // SecureStorage key for a given provider.
  static String _keyFor(String provider) => 'api_key_$provider';

  static Future<String> getSelectedProvider() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(kLlmProviderKey) ?? kProviderClaude;
  }

  static Future<void> setProvider(String provider) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(kLlmProviderKey, provider);
  }

  static Future<String> getApiKey(String provider) async {
    return (await _storage.read(key: _keyFor(provider)))?.trim() ?? '';
  }

  static Future<void> saveApiKey(String provider, String key) async {
    await _storage.write(key: _keyFor(provider), value: key.trim());
  }

  static Future<bool> hasKey(String provider) async =>
      (await getApiKey(provider)).isNotEmpty;

  // True when the currently selected provider has a key.
  static Future<bool> hasActiveKey() async =>
      hasKey(await getSelectedProvider());

  // Send [userPrompt] to whichever provider is currently selected.
  Future<String> complete(String systemPrompt, String userPrompt) async {
    final provider = await getSelectedProvider();
    final apiKey = await getApiKey(provider);

    if (apiKey.isEmpty) {
      return 'No API key for ${kProviderLabels[provider]}. '
          'Add one in Settings → AI provider.';
    }

    final model = _defaultModels[provider] ?? '';

    switch (provider) {
      case kProviderClaude:
        return _callAnthropic(apiKey, model, systemPrompt, userPrompt);
      case kProviderOpenAI:
        return _callOpenAICompat(
          'https://api.openai.com/v1/chat/completions',
          apiKey,
          model,
          systemPrompt,
          userPrompt,
        );
      case kProviderGemini:
        return _callGemini(apiKey, model, systemPrompt, userPrompt);
      case kProviderDeepSeek:
        return _callOpenAICompat(
          'https://api.deepseek.com/v1/chat/completions',
          apiKey,
          model,
          systemPrompt,
          userPrompt,
        );
      case kProviderOpenRouter:
        return _callOpenAICompat(
          'https://openrouter.ai/api/v1/chat/completions',
          apiKey,
          model,
          systemPrompt,
          userPrompt,
          extraHeaders: {
            'HTTP-Referer': 'https://github.com/foodwise',
            'X-Title': 'foodwise',
          },
        );
      default:
        return 'Unknown provider: $provider.';
    }
  }

  // ── Anthropic ──────────────────────────────────────────────────────────────

  Future<String> _callAnthropic(
    String apiKey,
    String model,
    String systemPrompt,
    String userPrompt,
  ) async {
    final response = await http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': 256,
        'system': systemPrompt,
        'messages': [
          {'role': 'user', 'content': userPrompt}
        ],
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final content = data['content'] as List<dynamic>;
      return (content.first as Map<String, dynamic>)['text'] as String;
    }
    return _errorMsg('Claude', response.statusCode, response.body);
  }

  // ── OpenAI-compatible (OpenAI, DeepSeek, OpenRouter) ──────────────────────

  Future<String> _callOpenAICompat(
    String url,
    String apiKey,
    String model,
    String systemPrompt,
    String userPrompt, {
    Map<String, String> extraHeaders = const {},
  }) async {
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
        ...extraHeaders,
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': 256,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>;
      final msg = (choices.first as Map<String, dynamic>)['message']
          as Map<String, dynamic>;
      return msg['content'] as String;
    }
    return _errorMsg(model, response.statusCode, response.body);
  }

  // ── Google Gemini ──────────────────────────────────────────────────────────

  Future<String> _callGemini(
    String apiKey,
    String model,
    String systemPrompt,
    String userPrompt,
  ) async {
    final url =
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey';
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'system_instruction': {
          'parts': [
            {'text': systemPrompt}
          ]
        },
        'contents': [
          {
            'parts': [
              {'text': userPrompt}
            ]
          }
        ],
        'generationConfig': {'maxOutputTokens': 256},
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>;
      final content =
          (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>;
      final parts = content['parts'] as List<dynamic>;
      return (parts.first as Map<String, dynamic>)['text'] as String;
    }
    return _errorMsg('Gemini', response.statusCode, response.body);
  }

  String _errorMsg(String provider, int code, String body) {
    // Surface the provider's own message when available.
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final msg = data['error']?['message'] as String?;
      if (msg != null && msg.isNotEmpty) {
        return '$provider error: $msg';
      }
    } catch (_) {}
    return '$provider error $code. Check your API key in Settings.';
  }
}
