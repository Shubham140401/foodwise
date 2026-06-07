import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/preferences_dao.dart';
import '../models/preference.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  String _dietType = 'none';
  int _numPeople = 1;
  final List<TextEditingController> _prefControllers = [TextEditingController()];
  final Set<String> _selectedCards = {};
  bool _saving = false;

  static const _dietOptions = ['none', 'vegetarian', 'vegan', 'non-vegetarian'];
  static const _bankOptions = [
    'HDFC', 'ICICI', 'SBI', 'Axis', 'Kotak',
    'Yes Bank', 'IDFC First', 'IndusInd', 'Citibank', 'AMEX',
  ];

  @override
  void dispose() {
    for (final c in _prefControllers) {
      c.dispose();
    }
    super.dispose();
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
    final prefs = Preference(
      dietType: _dietType,
      numPeople: _numPeople,
      peoplePreferences: _prefControllers.map((c) => c.text.trim()).toList(),
      bankCards: _selectedCards.toList(),
    );
    await context.read<PreferencesDao>().save(prefs);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('onboarding_done', true);
    if (mounted) widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Quick setup',
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      'foodwise learns your taste and budget from your order history. '
                      'Just tell it two things.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 36),

                    // Diet type
                    Text('Food type', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _dietOptions.map((d) {
                        final labels = {
                          'none': 'Everything',
                          'vegetarian': 'Vegetarian',
                          'vegan': 'Vegan',
                          'non-vegetarian': 'Non-veg',
                        };
                        return ChoiceChip(
                          label: Text(labels[d]!),
                          selected: _dietType == d,
                          onSelected: (_) => setState(() => _dietType = d),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 36),

                    // Number of people
                    Text('How many people are ordering?',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        IconButton.outlined(
                          onPressed: _numPeople > 1
                              ? () => _setPeopleCount(_numPeople - 1)
                              : null,
                          icon: const Icon(Icons.remove),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            '$_numPeople',
                            style: theme.textTheme.headlineSmall,
                          ),
                        ),
                        IconButton.outlined(
                          onPressed: _numPeople < 8
                              ? () => _setPeopleCount(_numPeople + 1)
                              : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // Per-person preference fields
                    Text(
                      _numPeople == 1
                          ? 'What do you usually like? (optional)'
                          : 'What does each person like? (optional)',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'e.g. "loves biryani", "vegetarian, no onion", "spicy food only"',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    for (int i = 0; i < _numPeople; i++) ...[
                      TextField(
                        controller: _prefControllers[i],
                        decoration: InputDecoration(
                          labelText: _numPeople == 1
                              ? 'Your preference'
                              : 'Person ${i + 1}',
                          border: const OutlineInputBorder(),
                          hintText: 'e.g. loves biryani, no egg',
                        ),
                      ),
                      if (i < _numPeople - 1) const SizedBox(height: 12),
                    ],

                    const SizedBox(height: 32),

                    Text('Credit / debit cards you use',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'foodwise will highlight bank-specific coupons for your cards.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
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

                    const SizedBox(height: 32),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline,
                              size: 16,
                              color: theme.colorScheme.onSecondaryContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your data stays on this device. '
                              'foodwise learns your budget and cuisines from your order history.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color:
                                      theme.colorScheme.onSecondaryContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Get started'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
