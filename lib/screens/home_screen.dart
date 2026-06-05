import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/preferences_dao.dart';
import '../database/orders_dao.dart';
import '../database/coupons_dao.dart';
import '../database/feedback_dao.dart';
import '../database/usage_dao.dart';
import '../models/preference.dart';
import '../models/order.dart';
import '../models/usage_session.dart';
import '../models/feedback.dart';
import '../services/accessibility_service.dart';
import '../services/app_mode.dart';
import '../services/background_service.dart';
import '../services/claude_service.dart';
import '../services/usage_stats_service.dart';
import '../services/location_service.dart';
import '../services/rule_engine.dart';
import '../widgets/deal_card.dart';
import '../widgets/addon_suggestion.dart';
import '../widgets/intent_indicator.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  String? _recommendation;
  String? _error;
  List<DealResult> _deals = [];
  IntentSignal _signal = IntentSignal.lowIntent;
  int _totalMins = 0;
  bool _accessibilityEnabled = false;
  // Which engine produced the current recommendation: 'ai' or 'static'.
  String _activeMode = kRecModeStatic;
  // Live data received from accessibility service during this session
  final Map<String, AppLiveData> _liveData = {};

  late final AccessibilityDataService _accessibilitySvc;

  @override
  void initState() {
    super.initState();
    _accessibilitySvc = AccessibilityDataService();
    _accessibilitySvc.listenForUpdates(
      (data) => setState(() => _liveData[data.app] = data),
      onOrderConfirmed: _handleOrderConfirmed,
    );
    _load();
  }

  @override
  void dispose() {
    _accessibilitySvc.stopListening();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });

    try {
      final prefsDao = context.read<PreferencesDao>();
      final ordersDao = context.read<OrdersDao>();
      final couponsDao = context.read<CouponsDao>();
      final usageDao = context.read<UsageDao>();
      final usageSvc = context.read<UsageStatsService>();
      final locationSvc = context.read<LocationService>();
      final claudeSvc = context.read<ClaudeService>();
      final ruleEngine = context.read<RuleEngine>();

      _accessibilityEnabled = await _accessibilitySvc.isEnabled();

      // Pull any already-cached live data from the accessibility service
      final cached = await _accessibilitySvc.getAllLatestData();
      for (final d in cached) {
        _liveData[d.app] = d;
      }

      final prefs = await prefsDao.get() ?? _defaultPrefs();
      final recentOrders = await ordersDao.getRecent();
      final activeCoupons = await couponsDao.getActive();
      final badRestaurants = await ordersDao.getBadRatedRestaurants();

      final usageResults = await usageSvc.getTodayUsage();
      _totalMins = await usageSvc.getTotalFoodAppMins();
      _signal = ruleEngine.scoreIntent(_totalMins);

      for (final u in usageResults) {
        await usageDao.insertOrReplace(UsageSession(
          date: DateTime.now(),
          app: u.appName,
          totalMins: u.totalMins,
          openCount: 1,
          orderPlaced: false,
          signal: ruleEngine.intentLabel(_signal),
        ));
      }

      final locationLabel = await locationSvc.resolveLocationLabel(
        homeAddress: prefs.homeAddress,
        workAddress: prefs.workAddress,
      );

      // Use live delivery fees from accessibility data where available,
      // fall back to defaults otherwise.
      final deliveryFees = {
        for (final app in ['Swiggy', 'Zomato', 'Blinkit'])
          app: _liveData[app]?.lowestDeliveryFee ?? _defaultDeliveryFee(app),
      };
      final cartEstimates = {'Swiggy': 280, 'Zomato': 290, 'Blinkit': 260};
      final platformFees = {'Swiggy': 15, 'Zomato': 10, 'Blinkit': 5};

      // Merge any coupons spotted by accessibility into active coupons list
      final liveCouponCodes = _liveData.values
          .expand((d) => d.coupons)
          .toSet();

      _deals = ruleEngine.rankDeals([
        for (final app in ['Swiggy', 'Zomato', 'Blinkit'])
          ruleEngine.bestDeal(
            app: app,
            baseCart: cartEstimates[app]!,
            deliveryFee: deliveryFees[app]!,
            platformFee: platformFees[app]!,
            coupons: activeCoupons.where((c) => c.app == app).toList(),
            okAddons: prefs.okAddons,
          ),
      ]);

      final sp = await SharedPreferences.getInstance();

      // Show the background job's cached result immediately so the screen
      // feels instant. Then recompute fresh below and update if still mounted.
      final bgRec = sp.getString(kCachedRecKey);
      final bgMode = sp.getString(kCachedModeKey) ?? kRecModeStatic;
      if (bgRec != null && mounted) {
        setState(() {
          _recommendation = bgRec;
          _activeMode = bgMode;
          _loading = false;
        });
      }

      // Fresh computation — overrides the cache once ready.
      final chosenMode = sp.getString(kRecModeKey) ?? kRecModeStatic;
      final useAi = chosenMode == kRecModeAi && await claudeSvc.hasApiKey();

      final String rec;
      if (useAi) {
        rec = await claudeSvc.getRecommendation(
          prefs: prefs,
          recentOrders: recentOrders,
          activeCoupons: activeCoupons,
          badRestaurants: badRestaurants,
          totalFoodAppMins: _totalMins,
          locationLabel: locationLabel,
          cartEstimates: cartEstimates,
          deliveryFees: deliveryFees,
          platformFees: platformFees,
          liveBanners: _liveData.map((k, v) => MapEntry(k, v.banners)),
          liveCouponCodes: liveCouponCodes.toList(),
        );
      } else {
        rec = ruleEngine.staticRecommendation(
          ranked: _deals,
          signal: _signal,
          meal: ruleEngine.mealType(),
          budget: ruleEngine.maxBudget(prefs),
          favRestaurant: _mostFrequentRestaurant(recentOrders),
        );
      }

      // Persist fresh result so the next background cycle has a baseline.
      await sp.setString(kCachedRecKey, rec);
      await sp.setString(kCachedModeKey, useAi ? kRecModeAi : kRecModeStatic);
      await sp.setInt(kCachedRecTimeKey, DateTime.now().millisecondsSinceEpoch);

      if (mounted) {
        setState(() {
          _recommendation = rec;
          _activeMode = useAi ? kRecModeAi : kRecModeStatic;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  int _defaultDeliveryFee(String app) =>
      const {'Swiggy': 40, 'Zomato': 35, 'Blinkit': 30}[app] ?? 40;

  // Most-ordered restaurant in recent history, for the static recommender.
  String? _mostFrequentRestaurant(List<Order> orders) {
    if (orders.isEmpty) return null;
    final counts = <String, int>{};
    for (final o in orders) {
      counts[o.restaurant] = (counts[o.restaurant] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  Preference _defaultPrefs() => const Preference(
        dietType: 'none',
        favCuisines: [],
        avoidItems: [],
        maxSpendLunch: 300,
        maxSpendDinner: 500,
        okAddons: [],
        paymentMethods: [],
      );

  Future<void> _handleOrderConfirmed(String app, DateTime at) async {
    final usageDao = context.read<UsageDao>();
    await usageDao.markOrderPlaced(app, at);
  }

  Future<void> _logFeedback(String satisfaction) async {
    final feedbackDao = context.read<FeedbackDao>();
    await feedbackDao.insert(FeedbackEntry(
      orderId: 'session_${DateTime.now().millisecondsSinceEpoch}',
      followedAgent: satisfaction == 'good',
      satisfaction: satisfaction,
      agentWasRight: satisfaction == 'good',
      ratedAt: DateTime.now(),
    ));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Thanks for the feedback!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('foodwise'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError()
                : _buildContent(theme),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final topDeal = _deals.isNotEmpty ? _deals.first : null;
    final addonSuggestion = topDeal?.addonSuggestion;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Accessibility permission nudge
        if (!_accessibilityEnabled)
          _buildAccessibilityBanner(theme),

        IntentIndicator(signal: _signal, totalMins: _totalMins),
        const SizedBox(height: 16),

        // Live data freshness indicator
        if (_liveData.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.circle, size: 8, color: Colors.green.shade600),
                const SizedBox(width: 6),
                Text(
                  'Live prices from ${_liveData.keys.join(", ")}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.green.shade700),
                ),
              ],
            ),
          ),

        // Claude recommendation card
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                        _activeMode == kRecModeAi
                            ? Icons.auto_awesome
                            : Icons.calculate_outlined,
                        size: 16,
                        color: theme.colorScheme.onPrimaryContainer),
                    const SizedBox(width: 6),
                    Text(
                        _activeMode == kRecModeAi
                            ? 'AI recommendation'
                            : 'Rule-based pick',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_recommendation ?? '',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
              ],
            ),
          ),
        ),

        if (addonSuggestion != null) ...[
          const SizedBox(height: 8),
          AddonSuggestion(suggestion: addonSuggestion),
        ],

        const SizedBox(height: 16),

        if (_signal != IntentSignal.decisionFatigue) ...[
          Text('All deals', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (int i = 0; i < _deals.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DealCard(deal: _deals[i], isTop: i == 0),
            ),
        ] else if (topDeal != null) ...[
          DealCard(deal: topDeal, isTop: true),
        ],

        const SizedBox(height: 16),

        Text('Was this helpful?', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => _logFeedback('good'),
              icon: const Icon(Icons.thumb_up_outlined, size: 16),
              label: const Text('Yes, ordered'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _logFeedback('ok'),
              icon: const Icon(Icons.thumbs_up_down_outlined, size: 16),
              label: const Text('Skipped'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _logFeedback('bad'),
              icon: const Icon(Icons.thumb_down_outlined, size: 16),
              label: const Text('Wrong'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAccessibilityBanner(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 18, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Enable accessibility to get live prices from Swiggy & Zomato',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
          TextButton(
            onPressed: _accessibilitySvc.openSettings,
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }
}
