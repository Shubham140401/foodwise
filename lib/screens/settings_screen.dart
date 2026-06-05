import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/preferences_dao.dart';
import '../models/preference.dart';
import '../services/app_mode.dart';
import '../services/llm_service.dart';
import 'import_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _homeController = TextEditingController();
  final _workController = TextEditingController();

  // One controller per provider so the user can type all keys before saving.
  final Map<String, TextEditingController> _keyControllers = {
    for (final p in kAllProviders) p: TextEditingController(),
  };
  final Map<String, bool> _obscure = {
    for (final p in kAllProviders) p: true,
  };

  String _recMode = kRecModeStatic;
  String _provider = kProviderClaude;
  bool _saving = false;
  Preference? _prefs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    // Load all stored keys in parallel.
    final keyFutures = {
      for (final p in kAllProviders) p: LlmService.getApiKey(p),
    };
    final keys = {
      for (final entry in keyFutures.entries) entry.key: await entry.value,
    };
    if (!mounted) return;
    final prefs = await context.read<PreferencesDao>().get();
    if (!mounted) return;
    setState(() {
      _recMode = sp.getString(kRecModeKey) ?? kRecModeStatic;
      _provider = sp.getString(kLlmProviderKey) ?? kProviderClaude;
      _prefs = prefs;
      _homeController.text = prefs?.homeAddress ?? '';
      _workController.text = prefs?.workAddress ?? '';
      for (final p in kAllProviders) {
        _keyControllers[p]!.text = keys[p] ?? '';
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    // Save all non-empty keys.
    for (final p in kAllProviders) {
      final val = _keyControllers[p]!.text.trim();
      if (val.isNotEmpty) await LlmService.saveApiKey(p, val);
    }

    // AI mode is only valid when the chosen provider has a key.
    var modeToSave = _recMode;
    if (modeToSave == kRecModeAi &&
        _keyControllers[_provider]!.text.trim().isEmpty) {
      modeToSave = kRecModeStatic;
    }

    final sp = await SharedPreferences.getInstance();
    await sp.setString(kRecModeKey, modeToSave);
    await LlmService.setProvider(_provider);

    if (_prefs != null && mounted) {
      await context.read<PreferencesDao>().save(_prefs!.copyWith(
            homeAddress: _homeController.text.trim().isEmpty
                ? null
                : _homeController.text.trim(),
            workAddress: _workController.text.trim().isEmpty
                ? null
                : _workController.text.trim(),
          ));
    }

    if (mounted) {
      setState(() {
        _saving = false;
        _recMode = modeToSave;
      });
      final msg = modeToSave != _recMode
          ? 'Saved. AI mode needs an API key — using Static mode.'
          : 'Settings saved';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _homeController.dispose();
    _workController.dispose();
    for (final c in _keyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Recommendation mode ──────────────────────────────────────────
          Text('Recommendation engine', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: kRecModeStatic,
                label: Text('Static'),
                icon: Icon(Icons.calculate_outlined),
              ),
              ButtonSegment(
                value: kRecModeAi,
                label: Text('AI'),
                icon: Icon(Icons.auto_awesome),
              ),
            ],
            selected: {_recMode},
            onSelectionChanged: (s) => setState(() => _recMode = s.first),
          ),
          const SizedBox(height: 6),
          Text(
            _recMode == kRecModeAi
                ? 'AI sends your deal context to an LLM for a smarter pick. '
                    'Select a provider and add its API key below.'
                : 'Static mode runs entirely on your device. '
                    'No API key needed, nothing leaves your phone.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),

          // ── Provider picker + keys (only in AI mode) ─────────────────────
          if (_recMode == kRecModeAi) ...[
            const SizedBox(height: 20),
            Text('AI provider', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _provider,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
              items: kAllProviders
                  .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(kProviderLabels[p]!),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _provider = v);
              },
            ),
            const SizedBox(height: 16),
            Text('API keys', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Only the selected provider\'s key is used. '
              'You can store keys for multiple providers here.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (final p in kAllProviders) _buildKeyField(theme, p),
          ],

          // ── Delivery addresses ───────────────────────────────────────────
          const SizedBox(height: 24),
          Text('Delivery addresses', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _homeController,
            decoration: const InputDecoration(
              labelText: 'Home address',
              prefixIcon: Icon(Icons.home_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _workController,
            decoration: const InputDecoration(
              labelText: 'Work address',
              prefixIcon: Icon(Icons.work_outline),
              border: OutlineInputBorder(),
            ),
          ),

          // ── Order history import ─────────────────────────────────────────
          const SizedBox(height: 24),
          Text('Order history', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Import from Swiggy / Zomato CSV'),
            subtitle: const Text('Trains the agent on your past orders'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ImportScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyField(ThemeData theme, String provider) {
    final isActive = provider == _provider;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _keyControllers[provider],
        obscureText: _obscure[provider]!,
        decoration: InputDecoration(
          labelText: kProviderLabels[provider],
          hintText: kProviderKeyHints[provider],
          border: const OutlineInputBorder(),
          // Highlight the active provider's field.
          enabledBorder: isActive
              ? OutlineInputBorder(
                  borderSide: BorderSide(
                      color: theme.colorScheme.primary, width: 1.5),
                )
              : null,
          suffixIcon: IconButton(
            icon: Icon(_obscure[provider]!
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
            onPressed: () =>
                setState(() => _obscure[provider] = !_obscure[provider]!),
          ),
        ),
      ),
    );
  }
}
