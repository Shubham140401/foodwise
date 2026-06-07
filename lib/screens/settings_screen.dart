import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/preferences_dao.dart';
import '../models/preference.dart';
import '../services/app_mode.dart';
import '../services/llm_service.dart';
import 'coupons_screen.dart';
import 'import_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Map<String, TextEditingController> _keyControllers = {
    for (final p in kAllProviders) p: TextEditingController(),
  };
  final Map<String, bool> _obscure = {
    for (final p in kAllProviders) p: true,
  };

  String _recMode = kRecModeStatic;
  String _provider = kProviderClaude;
  bool _saving = false;

  // Preferences state
  String _dietType = 'none';
  int _numPeople = 1;
  List<TextEditingController> _prefControllers = [TextEditingController()];
  final Set<String> _selectedCards = {};

  static const _dietOptions = ['none', 'vegetarian', 'vegan', 'non-vegetarian'];
  static const _bankOptions = [
    'HDFC', 'ICICI', 'SBI', 'Axis', 'Kotak',
    'Yes Bank', 'IDFC First', 'IndusInd', 'Citibank', 'AMEX',
  ];
  final _dietLabels = {
    'none': 'Everything',
    'vegetarian': 'Vegetarian',
    'vegan': 'Vegan',
    'non-vegetarian': 'Non-veg',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
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
      if (prefs != null) {
        _dietType = prefs.dietType;
        _numPeople = prefs.numPeople;
        _prefControllers = List.generate(
          prefs.numPeople,
          (i) => TextEditingController(
              text: i < prefs.peoplePreferences.length
                  ? prefs.peoplePreferences[i]
                  : ''),
        );
        _selectedCards
          ..clear()
          ..addAll(prefs.bankCards);
      }
      for (final p in kAllProviders) {
        _keyControllers[p]!.text = keys[p] ?? '';
      }
    });
  }

  void _setPeopleCount(int count) {
    setState(() {
      _numPeople = count;
      while (_prefControllers.length < count) {
        _prefControllers.add(TextEditingController());
      }
      while (_prefControllers.length > count) {
        _prefControllers.removeLast().dispose();
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    for (final p in kAllProviders) {
      final val = _keyControllers[p]!.text.trim();
      if (val.isNotEmpty) await LlmService.saveApiKey(p, val);
    }

    var modeToSave = _recMode;
    if (modeToSave == kRecModeAi &&
        _keyControllers[_provider]!.text.trim().isEmpty) {
      modeToSave = kRecModeStatic;
    }

    final sp = await SharedPreferences.getInstance();
    await sp.setString(kRecModeKey, modeToSave);
    await LlmService.setProvider(_provider);

    if (mounted) {
      final newPrefs = Preference(
        dietType: _dietType,
        numPeople: _numPeople,
        peoplePreferences: _prefControllers.map((c) => c.text.trim()).toList(),
        bankCards: _selectedCards.toList(),
      );
      await context.read<PreferencesDao>().save(newPrefs);
    }

    if (mounted) {
      setState(() {
        _saving = false;
        _recMode = modeToSave;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Settings saved')));
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    for (final c in _keyControllers.values) {
      c.dispose();
    }
    for (final c in _prefControllers) {
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
          // ── Who's ordering ───────────────────────────────────────────────
          Text('Who\'s ordering', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          Text('Food type', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _dietOptions.map((d) => ChoiceChip(
              label: Text(_dietLabels[d]!),
              selected: _dietType == d,
              onSelected: (_) => setState(() => _dietType = d),
            )).toList(),
          ),
          const SizedBox(height: 20),
          Text('People ordering', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.outlined(
                onPressed: _numPeople > 1 ? () => _setPeopleCount(_numPeople - 1) : null,
                icon: const Icon(Icons.remove),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('$_numPeople', style: theme.textTheme.titleLarge),
              ),
              IconButton.outlined(
                onPressed: _numPeople < 8 ? () => _setPeopleCount(_numPeople + 1) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < _numPeople; i++) ...[
            TextField(
              controller: _prefControllers[i],
              decoration: InputDecoration(
                labelText: _numPeople == 1 ? 'Your preference (optional)' : 'Person ${i + 1} (optional)',
                hintText: 'e.g. loves biryani, no egg',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (i < _numPeople - 1) const SizedBox(height: 10),
          ],

          // ── Bank cards ───────────────────────────────────────────────────
          const SizedBox(height: 24),
          Text('Credit / debit cards', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'foodwise highlights bank-specific coupons for your cards.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _bankOptions.map((bank) {
              final selected = _selectedCards.contains(bank);
              return FilterChip(
                label: Text(bank),
                selected: selected,
                onSelected: (_) => setState(() {
                  selected
                      ? _selectedCards.remove(bank)
                      : _selectedCards.add(bank);
                }),
              );
            }).toList(),
          ),

          // ── Recommendation mode ──────────────────────────────────────────
          const SizedBox(height: 28),
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

          // ── Coupons ──────────────────────────────────────────────────────
          const SizedBox(height: 24),
          Text('Coupons', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'foodwise auto-reads coupons while scraping. '
            'Add any from promo emails or SMS here.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.discount_outlined),
            title: const Text('Manage coupons'),
            subtitle: const Text('View, add, or delete stored coupon codes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CouponsScreen()),
            ),
          ),

          // ── Order history import ─────────────────────────────────────────
          const SizedBox(height: 16),
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
