import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'app_mode.dart';

const _taskUniqueName = 'foodwise.dealCheck';
const _taskName = 'dealCheck';

// Keys read by HomeScreen to show a prompt instantly on open.
const kCachedRecKey = 'cached_recommendation';
const kCachedRecTimeKey = 'cached_recommendation_time';
const kCachedModeKey = 'cached_recommendation_mode';

// Usage stats cached by HomeScreen so the background job can personalise
// notifications without needing a Flutter engine in the WorkManager isolate.
const kCachedFoodAppMinsKey = 'cached_food_app_mins';
const kCachedFoodAppMinsTimeKey = 'cached_food_app_mins_time';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {}

    if (task == _taskName) {
      await _runMealReminder();
    }
    return true;
  });
}

Future<void> _runMealReminder() async {
  final now = DateTime.now();
  final hour = now.hour;

  // Only fire during meal windows.
  final String meal;
  if (hour >= 11 && hour < 14) {
    meal = 'lunch';
  } else if (hour >= 19 && hour < 23) {
    meal = 'dinner';
  } else if (hour == 23) {
    meal = 'late_night';
  } else {
    return; // outside meal window — do nothing
  }

  // Throttle: at most one notification per 90 minutes.
  final sp = await SharedPreferences.getInstance();
  final lastMs = sp.getInt(kCachedRecTimeKey) ?? 0;
  final sinceLastMin = (now.millisecondsSinceEpoch - lastMs) ~/ 60000;
  if (sinceLastMin < 90) return;

  // Don't notify if onboarding hasn't been completed.
  if (!(sp.getBool('onboarding_done') ?? false)) return;

  final title = switch (meal) {
    'lunch'      => 'Lunch time',
    'dinner'     => 'Dinner time',
    'late_night' => 'Late night craving?',
    _            => 'Time to eat?',
  };

  // Read usage stats cached by HomeScreen — lets us personalise without
  // needing a Flutter engine or MethodChannel in the WorkManager isolate.
  final cachedMins = sp.getInt(kCachedFoodAppMinsKey) ?? 0;
  final cachedMinsTimeMs = sp.getInt(kCachedFoodAppMinsTimeKey) ?? 0;
  final minsSinceCache =
      (now.millisecondsSinceEpoch - cachedMinsTimeMs) ~/ 60000;
  final usageFresh = minsSinceCache < 30;

  final String body;
  if (usageFresh && cachedMins >= 16) {
    // Decision fatigue: they've been scrolling forever — cut through the noise
    body = "You've been browsing ${cachedMins}m — tap to see the 3 clearest picks.";
  } else if (usageFresh && cachedMins >= 5) {
    // Active on food apps: they're clearly hungry, pull them in quickly
    body = "You've been in food apps ${cachedMins}m — tap to compare live prices instantly.";
  } else {
    body = 'Open foodwise to compare live prices on Swiggy & Zomato.';
  }

  // Cache a neutral prompt so HomeScreen has something to show instantly
  // while the live scrape runs after the user taps the notification.
  await sp.setString(kCachedRecKey, body);
  await sp.setInt(kCachedRecTimeKey, now.millisecondsSinceEpoch);
  await sp.setString(kCachedModeKey, kRecModeStatic);

  await _sendNotification(title: title, body: body);
}

Future<void> _sendNotification({
  required String title,
  required String body,
}) async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidInit));

  await plugin.show(
    42, // fixed ID — replaces the previous notification instead of stacking
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'foodwise_deals',
        'Deal alerts',
        channelDescription: 'Meal-time reminder to check live food deals',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}

class BackgroundService {
  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  /// Registers the periodic meal reminder. Runs every 15 min (Android minimum).
  /// The task body exits immediately when outside meal windows.
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

  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(_taskUniqueName);
  }
}
