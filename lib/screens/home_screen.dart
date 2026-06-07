import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';

import '../database/preferences_dao.dart';
import '../database/orders_dao.dart';
import '../database/coupons_dao.dart';
import '../database/feedback_dao.dart';
import '../database/usage_dao.dart';
import '../models/food_item.dart';
import '../models/order.dart';
import '../models/preference.dart';
import '../models/usage_session.dart';
import '../models/feedback.dart';
import '../services/accessibility_service.dart';
import '../services/app_mode.dart';
import '../services/background_service.dart';
import '../services/claude_service.dart';
import '../services/usage_stats_service.dart';
import '../services/location_service.dart';
import '../services/rule_engine.dart';
import '../widgets/food_item_card.dart';
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
  bool _scraping = false;
  String? _error;

  // The user's craving for this session — drives what gets scraped and recommended
  // TODO(test): default to 'pizza' for debugging — remove before release
  String _query = 'pizza';
  final _queryController = TextEditingController(text: 'pizza');

  // Usage-stats-driven query suggestion
  bool _autoSuggested = false;   // true when query was pre-filled from history
  bool _suggestionDismissed = false; // true after user explicitly clears the field

  List<FoodItem> _foodItems = [];
  IntentSignal _signal = IntentSignal.lowIntent;
  int _totalMins = 0;
  bool _accessibilityEnabled = false;
  bool _usageStatsGranted = true;   // assumed granted until checked
  bool _fromNotification = false;   // true when app was opened by tapping a meal notification
  String _activeMode = kRecModeStatic;

  final Map<String, AppLiveData> _liveData = {};
  late final AccessibilityDataService _accessibilitySvc;

  // Quick-pick craving chips shown below the search field
  static const _quickChips = [
    'Non-veg', 'Veg', 'Biryani', 'Pizza',
    'Chinese', 'South Indian', 'Healthy', 'Thali',
  ];

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
    _queryController.dispose();
    super.dispose();
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });

    // Capture all providers before any await so BuildContext is not used
    // across async gaps.
    final prefsDao    = context.read<PreferencesDao>();
    final ordersDao   = context.read<OrdersDao>();
    final couponsDao  = context.read<CouponsDao>();
    final usageDao    = context.read<UsageDao>();
    final usageSvc    = context.read<UsageStatsService>();
    final ruleEngine  = context.read<RuleEngine>();
    final claudeSvc   = context.read<ClaudeService>();
    final locationSvc = context.read<LocationService>();

    try {
      _accessibilityEnabled = await _accessibilitySvc.isEnabled();
      _usageStatsGranted   = await _accessibilitySvc.isUsageStatsGranted();

      final cached = await _accessibilitySvc.getAllLatestData();
      for (final d in cached) { _liveData[d.app] = d; }

      final prefs        = await prefsDao.get() ?? _defaultPrefs();
      final recentOrders = await ordersDao.getRecent();
      final activeCoupons = await couponsDao.getActive();

      final usageResults = await usageSvc.getTodayUsage();
      _totalMins = await usageSvc.getTotalFoodAppMins();
      _signal    = ruleEngine.scoreIntent(_totalMins);

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

      // Cache usage stats to SharedPreferences so the background job can read
      // them without needing a Flutter engine or platform channel.
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(kCachedFoodAppMinsKey, _totalMins);
      await sp.setInt(
          kCachedFoodAppMinsTimeKey, DateTime.now().millisecondsSinceEpoch);

      // Detect notification-open: background job stamped kCachedRecTimeKey
      // when it fired. If that stamp is < 5 min old and this is the initial
      // load, the user tapped the meal notification to open the app.
      if (!silent) {
        final notifMs = sp.getInt(kCachedRecTimeKey) ?? 0;
        final notifAgeMin =
            (DateTime.now().millisecondsSinceEpoch - notifMs) ~/ 60000;
        _fromNotification = notifAgeMin < 5;
        // Clear the stamp so refreshes don't keep showing the banner.
        if (_fromNotification) await sp.remove(kCachedRecTimeKey);
      }

      // Auto-suggest a query from order history when the user is actively
      // browsing food apps but hasn't typed anything yet.
      if (!silent && _query.isEmpty && !_suggestionDismissed && _totalMins >= 5) {
        final meal = ruleEngine.mealType();
        final suggested = _suggestQueryFromHistory(recentOrders, meal);
        if (suggested != null && mounted) {
          setState(() {
            _query = suggested;
            _queryController.text = suggested;
            _autoSuggested = true;
          });
        }
      }

      // Only show food item results if we have a query and scraped food items
      final hasItems = _liveData.values.any((d) => d.foodItems.isNotEmpty);
      debugPrint('FoodwiseDart: _load query="$_query" hasItems=$hasItems '
          'liveItems=${_liveData.values.fold(0, (s, d) => s + d.foodItems.length)}');
      if (_query.isNotEmpty && hasItems) {
        final sp = await SharedPreferences.getInstance();
        final chosenMode = sp.getString(kRecModeKey) ?? kRecModeStatic;
        final locationLabel = await locationSvc.resolveLocationLabel();
        final badRestaurants = await ordersDao.getBadRatedRestaurants();
        final useAi = chosenMode == kRecModeAi && await claudeSvc.hasApiKey();

        if (useAi) {
          _foodItems = await claudeSvc.getFoodRecommendations(
            query: _query,
            prefs: prefs,
            recentOrders: recentOrders,
            activeCoupons: activeCoupons,
            badRestaurants: badRestaurants,
            totalFoodAppMins: _totalMins,
            locationLabel: locationLabel,
            liveData: _liveData,
          );
          _activeMode = kRecModeAi;
        } else {
          _foodItems = _staticFoodItems(ruleEngine, prefs, recentOrders);
          _activeMode = kRecModeStatic;
        }
      } else {
        _foodItems = [];
      }

      debugPrint('FoodwiseDart: _load built _foodItems=${_foodItems.length} '
          'mode=$_activeMode');

      if (mounted) {
        setState(() { _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }

    // After initial load, kick off scraping in the background
    if (!silent) _runBackgroundScrape();
  }

  // Build the recommendation list from live scraped data:
  //  • coupons come from offers visible on screen RIGHT NOW (not history/DB)
  //  • final price = item − live discount + packaging + platform + GST + delivery
  //  • results ranked by preference: diet (veg/non-veg) + order-history affinity,
  //    cheapest all-in price as tie-breaker; top 30 returned
  List<FoodItem> _staticFoodItems(
    RuleEngine ruleEngine,
    Preference prefs,
    List<Order> history,
  ) {
    final items = _liveData.entries.expand((entry) {
      final app = entry.key;
      final data = entry.value;
      final offers = ruleEngine.parseLiveOffers(data.banners, data.coupons);
      return data.foodItems.map((f) {
        final offer = ruleEngine.bestOffer(offers, f.price);
        final bd = ruleEngine.computeBreakdown(
          itemPrice: f.price,
          deliveryFee: f.deliveryFee,
          offer: offer,
        );
        return FoodItem(
          name: f.name,
          restaurant: f.restaurant,
          platform: app,
          price: f.price,
          originalPrice: f.originalPrice,
          finalPrice: bd.finalPrice,
          discount: bd.discount,
          couponCode: offer?.label,
          deliveryFee: bd.deliveryFee,
          packaging: bd.packaging,
          gst: bd.gst,
          platformFee: bd.platformFee,
          deliveryTime: f.deliveryTime,
          rating: f.rating,
          isVeg: RuleEngine.classifyVeg(f.name),
        );
      });
    }).toList();

    return ruleEngine.rankByPreference(items, prefs.dietType, history, limit: 30);
  }

  // ── Background scrape ────────────────────────────────────────────────────

  Future<void> _runBackgroundScrape() async {
    if (!mounted || !_accessibilityEnabled) return;

    // Never run two scrapes at once. _load can fire more than once on startup
    // (initState + dependency changes); without this guard each call launches a
    // parallel scrape, and the interleaved tap gestures land on the wrong targets
    // (e.g. Swiggy's ADD / cart buttons).
    if (_scraping) return;

    // Don't auto-scrape on open — wait for the user to enter a query.
    if (_query.isEmpty) return;

    // Re-scrape if we have a query but no food items yet (even if data is "fresh"
    // — the cached data may be from a home-page scrape with no search query).
    final hasFoodItems = _liveData.values.any((d) => d.foodItems.isNotEmpty);
    final isStale = _liveData.isEmpty ||
        _liveData.values.any(
          (d) => DateTime.now().difference(d.scrapedAt).inMinutes > 30,
        );
    if (hasFoodItems && !isStale) return;

    setState(() => _scraping = true);

    List<AppLiveData> scraped = const [];
    try {
      // Zomato disabled for now (paste/typing unreliable on its RN field; pending
      // the custom-IME path). Swiggy only until its drill-in flow is solid.
      scraped = await _accessibilitySvc.searchAndScrape(
        query: _query,
        apps: const ['Swiggy'],
      );
    } finally {
      // Always clear the in-flight flag so the guard above can't deadlock.
      if (mounted) setState(() => _scraping = false);
    }

    debugPrint('FoodwiseDart: scrape returned ${scraped.length} app(s); '
        'items=${scraped.map((d) => "${d.app}:${d.foodItems.length}").join(",")}');

    if (!mounted) return;

    for (final d in scraped) {
      if (!_liveData.containsKey(d.app) ||
          d.scrapedAt.isAfter(_liveData[d.app]!.scrapedAt)) {
        _liveData[d.app] = d;
      }
    }

    debugPrint('FoodwiseDart: _liveData items='
        '${_liveData.values.fold(0, (s, d) => s + d.foodItems.length)}');

    // Rebuild the recommendation list whenever live data carries food items.
    // anyNew can be false even on a successful scrape: the service broadcasts
    // each scroll pass live (ACTION_FOOD_DATA), so the live _onData callback may
    // have already stored the same object before searchAndScrape returned. Gating
    // the rebuild on anyNew then leaves _foodItems empty. Gate on having items.
    final hasFood = _liveData.values.any((d) => d.foodItems.isNotEmpty);
    if (hasFood && mounted) await _load(silent: true);
  }

  // Called when user submits a new craving query
  Future<void> _onQuerySubmit(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || trimmed == _query) return;
    // Clear both the Dart map AND the Kotlin-side cache so getAllLatestData()
    // doesn't repopulate with the old home-page scrape on the next _load().
    await _accessibilitySvc.clearCache();
    setState(() {
      _query = trimmed;
      _queryController.text = trimmed;
      _foodItems = [];
      _liveData.clear();
      _autoSuggested = false;
    });
    await _load();
  }

  // ── Event handlers ───────────────────────────────────────────────────────

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
          .showSnackBar(const SnackBar(content: Text('Thanks!')));
    }
  }

  Preference _defaultPrefs() => const Preference(
        dietType: 'none',
        numPeople: 1,
        peoplePreferences: [],
      );

  // Maps quick-chips to keywords found in item names / restaurant names.
  static const _chipKeywords = {
    'Biryani':       ['biryani', 'biriyani'],
    'Pizza':         ['pizza'],
    'Chinese':       ['chinese', 'noodle', 'fried rice', 'manchurian', 'momos'],
    'South Indian':  ['dosa', 'idli', 'vada', 'uttapam', 'appam'],
    'Healthy':       ['salad', 'healthy', 'grilled', 'bowl'],
    'Thali':         ['thali', 'meal combo', 'thali meal'],
    'Non-veg':       ['chicken', 'mutton', 'fish', 'prawn', 'egg', 'meat'],
    'Veg':           ['paneer', 'palak', 'aloo', 'dal', 'rajma'],
  };

  /// Looks at [orders] for the same meal type and returns the chip label that
  /// best matches what the user usually orders at this time of day.
  /// Returns null when order history is too thin to make a confident call.
  String? _suggestQueryFromHistory(List<Order> orders, String currentMeal) {
    final mealOrders = orders.where((o) => o.mealType == currentMeal).toList();
    final target = mealOrders.isNotEmpty ? mealOrders : orders;
    if (target.isEmpty) return null;

    final counts = <String, int>{};
    for (final order in target) {
      String itemsText;
      try {
        final decoded = jsonDecode(order.itemsJson);
        itemsText = (decoded as List).join(' ').toLowerCase();
      } catch (_) {
        itemsText = order.itemsJson.toLowerCase();
      }
      itemsText += ' ${order.restaurant.toLowerCase()}';

      for (final entry in _chipKeywords.entries) {
        for (final kw in entry.value) {
          if (itemsText.contains(kw)) {
            counts[entry.key] = (counts[entry.key] ?? 0) + 1;
            break;
          }
        }
      }
    }

    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('foodwise'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: () => _load(),
                  child: _buildContent(theme),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Accessibility permission nudge
        if (!_accessibilityEnabled) _buildAccessibilityBanner(theme),

        // Usage stats permission nudge — shown until user grants it.
        // Without this permission, intent scoring always returns lowIntent
        // and the decision-fatigue / auto-suggest features don't activate.
        if (!_usageStatsGranted) _buildUsageStatsBanner(theme),

        // Notification-origin context — shown when user opened the app by
        // tapping a meal-time notification rather than launching it directly.
        if (_fromNotification)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.notifications_outlined,
                    size: 15,
                    color: theme.colorScheme.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Opened from meal reminder · '
                    '${context.read<RuleEngine>().mealType()} time',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: theme.colorScheme.onTertiaryContainer,
                  onPressed: () => setState(() => _fromNotification = false),
                ),
              ],
            ),
          ),

        IntentIndicator(signal: _signal, totalMins: _totalMins),
        const SizedBox(height: 16),

        // ── Craving input ────────────────────────────────────────────────
        TextField(
          controller: _queryController,
          decoration: InputDecoration(
            hintText: 'What are you craving today?',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _queryController.clear();
                      setState(() {
                        _query = '';
                        _foodItems = [];
                        _autoSuggested = false;
                        _suggestionDismissed = true;
                      });
                    },
                  )
                : null,
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          onSubmitted: _onQuerySubmit,
          textInputAction: TextInputAction.search,
        ),
        const SizedBox(height: 10),

        // Quick chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _quickChips.map((chip) {
              final selected = _query.toLowerCase() == chip.toLowerCase();
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(chip),
                  selected: selected,
                  onSelected: (_) => _onQuerySubmit(selected ? '' : chip),
                ),
              );
            }).toList(),
          ),
        ),

        // Show when query was pre-filled from order history
        if (_autoSuggested)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Icon(Icons.history, size: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Suggested from your order history',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),

        const SizedBox(height: 16),

        // ── Status strip ─────────────────────────────────────────────────
        if (_scraping)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _query.isNotEmpty
                        ? 'Searching "$_query" on Swiggy & Zomato…'
                        : 'Getting live prices from Swiggy & Zomato…',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          )
        else if (_liveData.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.circle, size: 8, color: Colors.green.shade600),
                const SizedBox(width: 6),
                Text(
                  'Live data from ${_liveData.keys.join(", ")}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.green.shade700),
                ),
              ],
            ),
          ),

        // ── Empty / prompt state ─────────────────────────────────────────
        if (_query.isEmpty && !_scraping)
          _buildEmptyPrompt(theme)

        // ── No results yet (query set, scraping in progress or just done) ─
        else if (_foodItems.isEmpty && _query.isNotEmpty && !_scraping)
          _buildNoResults(theme)

        // ── Food item results ────────────────────────────────────────────
        else if (_foodItems.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Top picks for "$_query"',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Icon(
                _activeMode == kRecModeAi
                    ? Icons.auto_awesome
                    : Icons.calculate_outlined,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                _activeMode == kRecModeAi ? 'AI' : 'Rule-based',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Always show the full ranked list (up to 30), regardless of intent.
          ...() {
            final display = _foodItems.take(30).toList();
            return [
              for (int i = 0; i < display.length; i++) ...[
                FoodItemCard(item: display[i], rank: i + 1),
                if (i < display.length - 1) const SizedBox(height: 8),
              ],
            ];
          }(),
          const SizedBox(height: 16),
          // Feedback row
          Text('Was this helpful?', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _logFeedback('good'),
                icon: const Icon(Icons.thumb_up_outlined, size: 16),
                label: const Text('Ordered'),
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
      ],
    );
  }

  Widget _buildEmptyPrompt(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.restaurant_menu_outlined,
              size: 56, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            'What do you feel like eating?',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Type a dish or tap a chip above.\n'
            'foodwise will search Swiggy & Zomato and show you\n'
            'the best deal after coupons.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.search_off_outlined,
              size: 48, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Text(
            'No results for "$_query" yet.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            _accessibilityEnabled
                ? 'Scrape finished but no items matched "$_query".\nTry a broader term like "chicken" or "biryani".'
                : 'Enable accessibility so foodwise can search\nSwiggy & Zomato for "$_query" automatically.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildUsageStatsBanner(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.bar_chart_outlined,
              size: 18, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Grant Usage Access so foodwise can detect when '
              'you\'re browsing food apps and suggest smarter picks',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
          TextButton(
            onPressed: _accessibilitySvc.openUsageStatsSettings,
            child: const Text('Grant'),
          ),
        ],
      ),
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
              'Enable accessibility so foodwise can search Swiggy & Zomato for you',
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
