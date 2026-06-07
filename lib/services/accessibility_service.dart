import 'dart:async';
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

class FoodItemLiveData {
  final String name;
  final String restaurant;
  final int price;          // effective (discounted) menu price
  final int originalPrice;  // struck-out price, or == price if not discounted
  final String rating;
  final String deliveryTime;
  final int deliveryFee;
  final String discount;

  const FoodItemLiveData({
    required this.name,
    required this.restaurant,
    required this.price,
    required this.originalPrice,
    required this.rating,
    required this.deliveryTime,
    required this.deliveryFee,
    required this.discount,
  });

  factory FoodItemLiveData.fromMap(Map<String, dynamic> map) => FoodItemLiveData(
        name: map['name'] as String? ?? '',
        restaurant: map['restaurant'] as String? ?? '',
        price: (map['price'] as int?) ?? 0,
        originalPrice: (map['originalPrice'] as int?) ?? (map['price'] as int?) ?? 0,
        rating: map['rating'] as String? ?? '',
        deliveryTime: map['deliveryTime'] as String? ?? '',
        deliveryFee: (map['deliveryFee'] as int?) ?? 0,
        discount: map['discount'] as String? ?? '',
      );
}

class AppLiveData {
  final String app;
  final List<RestaurantLiveData> restaurants;
  final List<FoodItemLiveData> foodItems;
  final List<String> coupons;
  final List<String> banners;
  final DateTime scrapedAt;

  const AppLiveData({
    required this.app,
    required this.restaurants,
    required this.foodItems,
    required this.coupons,
    required this.banners,
    required this.scrapedAt,
  });

  factory AppLiveData.fromMap(Map<String, dynamic> map) => AppLiveData(
        app: map['app'] as String,
        restaurants: (map['restaurants'] as List<dynamic>)
            .map((r) => RestaurantLiveData.fromMap(Map<String, dynamic>.from(r as Map)))
            .toList(),
        foodItems: ((map['foodItems'] as List<dynamic>?) ?? [])
            .map((f) => FoodItemLiveData.fromMap(Map<String, dynamic>.from(f as Map)))
            .toList(),
        coupons: List<String>.from(map['coupons'] as List),
        banners: List<String>.from(map['banners'] as List),
        scrapedAt: DateTime.fromMillisecondsSinceEpoch(map['scrapedAt'] as int),
      );

  int get lowestDeliveryFee {
    if (restaurants.isEmpty) return 40;
    return restaurants.map((r) => r.deliveryFee).reduce((a, b) => a < b ? a : b);
  }

  String? get bestBanner => banners.isNotEmpty ? banners.first : null;
}

class AccessibilityDataService {
  static const _channel = MethodChannel('com.foodwise/accessibility');

  // Stored callbacks — a single MethodCallHandler dispatches to all of them.
  void Function(AppLiveData)? _onData;
  void Function(String app, DateTime at)? _onOrderConfirmed;
  void Function()? _onScrapeDone;

  // Sets up the single MethodCallHandler. Called by listenForUpdates and
  // again by scrapeApps (which adds _onScrapeDone) without overwriting the
  // existing live-data and order-confirmed callbacks.
  void _initHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onFoodData':
          try {
            final json = call.arguments as String;
            final map = jsonDecode(json) as Map<String, dynamic>;
            _onData?.call(AppLiveData.fromMap(map));
          } catch (_) {}
          break;
        case 'onOrderConfirmed':
          try {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final app = args['app'] as String;
            final ts = args['timestamp'] as int;
            _onOrderConfirmed?.call(app, DateTime.fromMillisecondsSinceEpoch(ts));
          } catch (_) {}
          break;
        case 'onScrapeDone':
          _onScrapeDone?.call();
          break;
      }
    });
  }

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

  Future<bool> isUsageStatsGranted() async {
    try {
      return await _channel.invokeMethod<bool>('isUsageStatsGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearCache() async {
    try {
      await _channel.invokeMethod('clearCache');
    } catch (_) {}
  }

  Future<void> openUsageStatsSettings() async {
    try {
      await _channel.invokeMethod('openUsageStatsSettings');
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

  /// Register callbacks for live screen updates and order confirmation.
  /// Must be called before [scrapeApps] so the handler is initialised.
  void listenForUpdates(
    void Function(AppLiveData) onData, {
    void Function(String app, DateTime at)? onOrderConfirmed,
  }) {
    _onData = onData;
    _onOrderConfirmed = onOrderConfirmed;
    _initHandler();
  }

  void stopListening() {
    _onData = null;
    _onOrderConfirmed = null;
    _onScrapeDone = null;
    _channel.setMethodCallHandler(null);
  }

  /// Opens Swiggy and Zomato, reads home-page delivery fees and coupon banners,
  /// then returns to foodwise. Use this when no specific query is set.
  Future<List<AppLiveData>> scrapeApps({
    List<String> apps = const ['Swiggy', 'Zomato'],
    Duration timeout = const Duration(seconds: 35),
  }) => _scrape('scrapeApps', {'apps': apps}, timeout);

  /// Opens Swiggy and Zomato, navigates to search for [query] (e.g. "biryani",
  /// "non veg"), reads food item results, then returns to foodwise.
  Future<List<AppLiveData>> searchAndScrape({
    required String query,
    List<String> apps = const ['Swiggy', 'Zomato'],
    Duration timeout = const Duration(seconds: 105),
  }) => _scrape('searchAndScrape', {'query': query, 'apps': apps}, timeout);

  Future<List<AppLiveData>> _scrape(
    String method,
    Map<String, dynamic> args,
    Duration timeout,
  ) async {
    final completer = Completer<List<AppLiveData>>();

    _onScrapeDone = () async {
      _onScrapeDone = null;
      if (!completer.isCompleted) {
        completer.complete(await getAllLatestData());
      }
    };

    try {
      final serviceRunning =
          await _channel.invokeMethod<bool>(method, args) ?? false;
      if (!serviceRunning) {
        _onScrapeDone = null;
        return getAllLatestData();
      }
    } catch (_) {
      _onScrapeDone = null;
      return getAllLatestData();
    }

    return completer.future.timeout(
      timeout,
      onTimeout: () async {
        _onScrapeDone = null;
        return getAllLatestData();
      },
    );
  }
}
