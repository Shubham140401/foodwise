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
  final _pageController = PageController();
  int _page = 0;

  // Form state
  String _dietType = 'none';
  final _cuisineController = TextEditingController();
  final List<String> _cuisines = [];
  final _avoidController = TextEditingController();
  final List<String> _avoidItems = [];
  int _maxLunch = 300;
  int _maxDinner = 500;
  final _addonController = TextEditingController();
  final List<String> _addons = [];
  final List<String> _paymentMethods = [];
  final _homeController = TextEditingController();
  final _workController = TextEditingController();

  bool _saving = false;

  final _dietOptions = ['none', 'vegetarian', 'vegan', 'non-vegetarian'];
  final _paymentOptions = ['UPI', 'Credit Card', 'Debit Card', 'Cash', 'Wallet'];

  @override
  void dispose() {
    _pageController.dispose();
    _cuisineController.dispose();
    _avoidController.dispose();
    _addonController.dispose();
    _homeController.dispose();
    _workController.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < 3) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _save();
    }
  }

  void _prev() {
    _pageController.previousPage(
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final pref = Preference(
      dietType: _dietType,
      favCuisines: _cuisines,
      avoidItems: _avoidItems,
      maxSpendLunch: _maxLunch,
      maxSpendDinner: _maxDinner,
      okAddons: _addons,
      paymentMethods: _paymentMethods,
      homeAddress: _homeController.text.trim().isEmpty ? null : _homeController.text.trim(),
      workAddress: _workController.text.trim().isEmpty ? null : _workController.text.trim(),
    );
    await context.read<PreferencesDao>().save(pref);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('onboarding_done', true);
    if (mounted) widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildProgress(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (p) => setState(() => _page = p),
                children: [
                  _buildDietPage(),
                  _buildBudgetPage(),
                  _buildAddonsPaymentPage(),
                  _buildAddressPage(),
                ],
              ),
            ),
            _buildNavButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: (_page + 1) / 4),
          const SizedBox(height: 8),
          Text('Step ${_page + 1} of 4',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildNavButtons() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          if (_page > 0)
            OutlinedButton(onPressed: _prev, child: const Text('Back')),
          const Spacer(),
          FilledButton(
            onPressed: _saving ? null : _next,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_page == 3 ? 'Finish' : 'Next'),
          ),
        ],
      ),
    );
  }

  Widget _buildDietPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your food preferences',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          Text('Diet type', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _dietOptions
                .map((d) => ChoiceChip(
                      label: Text(d),
                      selected: _dietType == d,
                      onSelected: (_) => setState(() => _dietType = d),
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),
          Text('Favourite cuisines', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _chipInputRow(
              controller: _cuisineController,
              hint: 'e.g. Biryani, Pizza',
              items: _cuisines,
              onAdd: () {
                final v = _cuisineController.text.trim();
                if (v.isNotEmpty) setState(() { _cuisines.add(v); _cuisineController.clear(); });
              },
              onRemove: (i) => setState(() => _cuisines.removeAt(i))),
          const SizedBox(height: 24),
          Text('Items to avoid', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _chipInputRow(
              controller: _avoidController,
              hint: 'e.g. Mushroom, Egg',
              items: _avoidItems,
              onAdd: () {
                final v = _avoidController.text.trim();
                if (v.isNotEmpty) setState(() { _avoidItems.add(v); _avoidController.clear(); });
              },
              onRemove: (i) => setState(() => _avoidItems.removeAt(i))),
        ],
      ),
    );
  }

  Widget _buildBudgetPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Budget limits', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('The agent won\'t recommend orders above these amounts.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 32),
          Text('Max spend — Lunch: ₹$_maxLunch',
              style: Theme.of(context).textTheme.labelLarge),
          Slider(
            value: _maxLunch.toDouble(),
            min: 100, max: 1000, divisions: 18,
            label: '₹$_maxLunch',
            onChanged: (v) => setState(() => _maxLunch = v.round()),
          ),
          const SizedBox(height: 24),
          Text('Max spend — Dinner: ₹$_maxDinner',
              style: Theme.of(context).textTheme.labelLarge),
          Slider(
            value: _maxDinner.toDouble(),
            min: 100, max: 1500, divisions: 28,
            label: '₹$_maxDinner',
            onChanged: (v) => setState(() => _maxDinner = v.round()),
          ),
        ],
      ),
    );
  }

  Widget _buildAddonsPaymentPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add-ons & Payment', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('Add-ons you\'re OK adding to unlock coupons (cheap items).',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
          Text('OK add-ons', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _chipInputRow(
              controller: _addonController,
              hint: 'e.g. Coke, Bread',
              items: _addons,
              onAdd: () {
                final v = _addonController.text.trim();
                if (v.isNotEmpty) setState(() { _addons.add(v); _addonController.clear(); });
              },
              onRemove: (i) => setState(() => _addons.removeAt(i))),
          const SizedBox(height: 24),
          Text('Payment methods', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 4,
            children: _paymentOptions
                .map((p) => FilterChip(
                      label: Text(p),
                      selected: _paymentMethods.contains(p),
                      onSelected: (sel) => setState(() {
                        sel ? _paymentMethods.add(p) : _paymentMethods.remove(p);
                      }),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Delivery addresses', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('Used to pick the right delivery fee estimate.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
          TextField(
            controller: _homeController,
            decoration: const InputDecoration(
              labelText: 'Home address',
              prefixIcon: Icon(Icons.home_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _workController,
            decoration: const InputDecoration(
              labelText: 'Work address',
              prefixIcon: Icon(Icons.work_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('You can skip these and add them later in Settings.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }

  Widget _chipInputRow({
    required TextEditingController controller,
    required String hint,
    required List<String> items,
    required VoidCallback onAdd,
    required void Function(int) onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: hint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => onAdd(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: onAdd, icon: const Icon(Icons.add)),
          ],
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: items
                .asMap()
                .entries
                .map((e) => Chip(
                      label: Text(e.value),
                      onDeleted: () => onRemove(e.key),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }
}
