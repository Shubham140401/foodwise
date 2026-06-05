import 'dart:convert';

import 'package:flutter/services.dart';

class RestaurantLiveData {
  final String name;
  final int deliveryFee;
  final String deliveryTime;
  final String rating;
  final String discount;

  const RestaurantLiveData({
    required this.name,
    required this.deliveryFee,
    required this.deliveryTime,
    required this.rating,
    required this.discount,
  });

  factory RestaurantLiveData.fromMap(Map<String, dynamic> map) => RestaurantLiveData(
        name: map['name'] as String,
        deliveryFee: (map['deliveryFee'] as int?) ?? 0,
        deliveryTime: map['deliveryTime'] as String? ?? '',
        rating: map['rating'] as String? ?? '',
        discount: map['discount'] as String? ?? '',
      );
}

class AppLiveData {
  final String app;
  final List<RestaurantLiveData> restaurants;
  final List<String> coupons;
  final List<String> banners;
  final DateTime scrapedAt;

  const AppLiveData({
    required this.app,
    required this.restaurants,
    required this.coupons,
    required this.banners,
    required this.scrapedAt,
  });

  factory AppLiveData.fromMap(Map<String, dynamic> map) => AppLiveData(
        app: map['app'] as String,
        restaurants: (map['restaurants'] as List<dynamic>)
            .map((r) => RestaurantLiveData.fromMap(Map<String, dynamic>.from(r as Map)))
            .toList(),
        coupons: List<String>.from(map['coupons'] as List),
        banners: List<String>.from(map['banners'] as List),
        scrapedAt: DateTime.fromMillisecondsSinceEpoch(map['scrapedAt'] as int),
      );

  // Lowest delivery fee among scraped restaurants
  int get lowestDeliveryFee {
    if (restaurants.isEmpty) return 40;
    return restaurants.map((r) => r.deliveryFee).reduce((a, b) => a < b ? a : b);
  }

  // Best discount banner text
  String? get bestBanner => banners.isNotEmpty ? banners.first : null;
}

class AccessibilityDataService {
  static const _channel = MethodChannel('com.foodwise/accessibility');

  Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod('openSettings');
    } catch (_) {}
  }

  Future<AppLiveData?> getLatestData(String app) async {
    try {
      final result = await _channel.invokeMethod<Map>('getLatestData', {'app': app});
      if (result == null) return null;
      return AppLiveData.fromMap(Map<String, dynamic>.from(result));
    } catch (_) {
      return null;
    }
  }

  Future<List<AppLiveData>> getAllLatestData() async {
    try {
      final result = await _channel.invokeMethod<List>('getAllLatestData');
      if (result == null) return [];
      return result
          .map((item) => AppLiveData.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // Listen for real-time updates broadcast from the accessibility service
  void listenForUpdates(void Function(AppLiveData) onData) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onFoodData') {
        try {
          final json = call.arguments as String;
          final map = jsonDecode(json) as Map<String, dynamic>;
          onData(AppLiveData.fromMap(map));
        } catch (_) {}
      }
    });
  }

  void stopListening() {
    _channel.setMethodCallHandler(null);
  }
}
