import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../database/db_helper.dart';
import '../database/coupons_dao.dart';
import '../database/orders_dao.dart';
import '../database/preferences_dao.dart';
import 'app_mode.dart';
import 'claude_service.dart';
import 'rule_engine.dart';
import 'usage_stats_service.dart';

const _taskUniqueName = 'foodwise.dealCheck';
const _taskName = 'dealCheck';

// Keys for the recommendation cached by the background job.
// HomeScreen reads these to show a result instantly on open.
const kCachedRecKey = 'cached_recommendation';
const kCachedRecTimeKey = 'cached_recommendation_time';
const kCachedModeKey = 'cached_recommendation_mode';

// Called by WorkManager in a background Dart isolate.
// Must be a top-level function annotated with vm:entry-point.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // .env may not be accessible in some background contexts; ClaudeService
      // falls back to secure storage for the API key.
    }

    if (task == _taskName) {
      await _runDealCheck();
    }
    return true;
  });
}

Future<void> _runDealCheck() async {
  final hour = DateTime.now().hour;

  // Only run during meal windows — avoids irrelevant notifications.
  // Lunch 11:00–14:00, Dinner 19:00–22:00, Late night 22:00–23:59.
  final isMealTime = (hour >= 11 && hour < 14) ||
      (hour >= 19 && hour < 23) ||
      hour == 23;
  if (!isMealTime) return;

  // Throttle: don't notify more than once every 90 minutes.
  final sp = await SharedPreferences.getInstance();
  final lastMs = sp.getInt(kCachedRecTimeKey) ?? 0;
  final sinceLastMin =
      (DateTime.now().millisecondsSinceEpoch - lastMs) ~/ 60000;
  if (sinceLastMin < 90) return;

  final db = DbHelper();
  final ruleEngine = RuleEngine();
  final claudeSvc = ClaudeService(ruleEngine);
  final prefsDao = PreferencesDao(db);
  final ordersDao = OrdersDao(db);
  final couponsDao = CouponsDao(db);
  final usageSvc = UsageStatsService();

  final prefs = await prefsDao.get();
  if (prefs == null) return; // onboarding not done yet

  final recentOrders = await ordersDao.getRecent();
  final activeCoupons = await couponsDao.getActive();
  final badRestaurants = await ordersDao.getBadRatedRestaurants();

  int totalMins = 0;
  try {
    totalMins = await usageSvc.getTotalFoodAppMins();
  } catch (_) {}

  final signal = ruleEngine.scoreIntent(totalMins);
  final meal = ruleEngine.mealType();
  final budget = ruleEngine.maxBudget(prefs);

  final cartEstimates = {'Swiggy': 280, 'Zomato': 290, 'Blinkit': 260};
  final deliveryFees = {'Swiggy': 40, 'Zomato': 35, 'Blinkit': 30};
  final platformFees = {'Swiggy': 15, 'Zomato': 10, 'Blinkit': 5};

  final deals = ruleEngine.rankDeals([
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

  final chosenMode = sp.getString(kRecModeKey) ?? kRecModeStatic;
  final useAi = chosenMode == kRecModeAi && await claudeSvc.hasApiKey();

  String recommendation;
  String modeUsed;

  if (useAi) {
    try {
      recommendation = await claudeSvc.getRecommendation(
        prefs: prefs,
        recentOrders: recentOrders,
        activeCoupons: activeCoupons,
        badRestaurants: badRestaurants,
        totalFoodAppMins: totalMins,
        locationLabel: 'your area',
        cartEstimates: cartEstimates,
        deliveryFees: deliveryFees,
        platformFees: platformFees,
      );
      modeUsed = kRecModeAi;
    } catch (_) {
      recommendation = ruleEngine.staticRecommendation(
        ranked: deals,
        signal: signal,
        meal: meal,
        budget: budget,
      );
      modeUsed = kRecModeStatic;
    }
  } else {
    recommendation = ruleEngine.staticRecommendation(
      ranked: deals,
      signal: signal,
      meal: meal,
      budget: budget,
    );
    modeUsed = kRecModeStatic;
  }

  // Cache so HomeScreen can show it instantly on next open.
  await sp.setString(kCachedRecKey, recommendation);
  await sp.setInt(kCachedRecTimeKey, DateTime.now().millisecondsSinceEpoch);
  await sp.setString(kCachedModeKey, modeUsed);
  await sp.setString(
    'cached_deals',
    jsonEncode(deals
        .map((d) => {
              'app': d.app,
              'finalPrice': d.finalPrice,
              'discount': d.discount,
              'saving': d.saving,
              'addonSuggestion': d.addonSuggestion,
              'couponCode': d.bestCoupon?.code,
            })
        .toList()),
  );

  await _sendNotification(
    recommendation: recommendation,
    bestApp: deals.isNotEmpty ? deals.first.app : null,
    bestPrice: deals.isNotEmpty ? deals.first.finalPrice : null,
  );
}

Future<void> _sendNotification({
  required String recommendation,
  String? bestApp,
  int? bestPrice,
}) async {
  final plugin = FlutterLocalNotificationsPlugin();

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidInit));

  final title = bestApp != null && bestPrice != null
      ? 'Best deal: $bestApp at ₹$bestPrice'
      : 'foodwise found a deal for you';

  final body = recommendation.length > 200
      ? '${recommendation.substring(0, 197)}...'
      : recommendation;

  await plugin.show(
    42, // fixed ID — replaces instead of stacking notifications
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'foodwise_deals',
        'Deal alerts',
        channelDescription: 'Proactive food deal recommendations',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(''),
      ),
    ),
  );
}

class BackgroundService {
  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  /// Registers the periodic deal-check. Runs every 15 min (Android minimum).
  /// The task body skips silently when outside meal windows.
  static Future<void> registerPeriodicTask() async {
    await Workmanager().registerPeriodicTask(
      _taskUniqueName,
      _taskName,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 1),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
      ),
    );
  }

  /// Fires a one-off check immediately — used when the AccessibilityService
  /// detects the user just opened a food app.
  static Future<void> runImmediateCheck() async {
    await Workmanager().registerOneOffTask(
      '$_taskUniqueName.immediate',
      _taskName,
      initialDelay: Duration.zero,
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(_taskUniqueName);
  }
}
