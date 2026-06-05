import 'package:app_usage/app_usage.dart';

const _foodApps = {
  'com.application.zomato': 'Zomato',
  'in.swiggy.android': 'Swiggy',
  'com.blinkit.consumer': 'Blinkit',
};

class AppUsageResult {
  final String appName;
  final int totalMins;

  const AppUsageResult({required this.appName, required this.totalMins});
}

class UsageStatsService {
  Future<List<AppUsageResult>> getTodayUsage() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final stats = await AppUsage().getAppUsage(startOfDay, now);

      final results = <AppUsageResult>[];
      for (final entry in stats) {
        final label = _foodApps[entry.packageName];
        if (label != null) {
          results.add(AppUsageResult(
            appName: label,
            totalMins: entry.usage.inMinutes,
          ));
        }
      }
      return results;
    } catch (_) {
      // Permission not granted or API unavailable — return empty list.
      return [];
    }
  }

  // Returns total minutes across all food apps today.
  Future<int> getTotalFoodAppMins() async {
    final usage = await getTodayUsage();
    return usage.fold<int>(0, (sum, r) => sum + r.totalMins);
  }
}
