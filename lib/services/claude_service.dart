import 'dart:convert';

import '../models/coupon.dart';
import '../models/food_item.dart';
import '../models/order.dart';
import '../models/preference.dart';
import '../services/accessibility_service.dart';
import 'llm_service.dart';
import 'rule_engine.dart';

const _systemPrompt =
    'You are a personal food ordering agent. Be concise and specific. '
    'Always show true final prices including delivery fee. '
    'Respond ONLY with a valid JSON array — no markdown, no explanation.';

class ClaudeService {
  final RuleEngine _ruleEngine;
  final LlmService _llm;

  ClaudeService(this._ruleEngine) : _llm = LlmService();

  Future<bool> hasApiKey() => LlmService.hasActiveKey();

  /// Returns up to 10 ranked [FoodItem] recommendations.
  /// [query] is what the user said they want today (e.g. "non-veg biryani").
  Future<List<FoodItem>> getFoodRecommendations({
    required String query,
    required Preference prefs,
    required List<Order> recentOrders,
    required List<Coupon> activeCoupons,
    required List<String> badRestaurants,
    required int totalFoodAppMins,
    required String locationLabel,
    required Map<String, AppLiveData> liveData,
  }) async {
    final signal = _ruleEngine.scoreIntent(totalFoodAppMins);
    final signalLabel = _ruleEngine.intentLabel(signal);
    final meal = _ruleEngine.mealType();
    final budget = _ruleEngine.maxBudget(recentOrders);

    final userPrompt = _buildPrompt(
      query: query,
      prefs: prefs,
      meal: meal,
      budget: budget,
      signalLabel: signalLabel,
      totalMins: totalFoodAppMins,
      locationLabel: locationLabel,
      liveData: liveData,
      activeCoupons: activeCoupons,
      topRestaurants: _topRestaurants(recentOrders),
      badRestaurants: badRestaurants,
      bankCards: prefs.bankCards,
    );

    final raw = await _llm.complete(_systemPrompt, userPrompt);
    return _parseFoodItems(raw, liveData, activeCoupons);
  }

  String _buildPrompt({
    required String query,
    required Preference prefs,
    required String meal,
    required int budget,
    required String signalLabel,
    required int totalMins,
    required String locationLabel,
    required Map<String, AppLiveData> liveData,
    required List<Coupon> activeCoupons,
    required List<String> topRestaurants,
    required List<String> badRestaurants,
    required List<String> bankCards,
  }) {
    // Build scraped food items block
    final scrapedBlock = liveData.entries.map((e) {
      final app = e.key;
      final data = e.value;
      if (data.foodItems.isEmpty && data.restaurants.isEmpty) {
        return '$app: no live data';
      }
      final items = data.foodItems.isNotEmpty
          ? data.foodItems
              .map((f) =>
                  '  ${f.name} @ ${f.restaurant}: ₹${f.price}, ${f.deliveryTime}, '
                  '${f.deliveryFee > 0 ? "₹${f.deliveryFee} delivery" : "free delivery"}'
                  '${f.rating.isNotEmpty ? ", ⭐${f.rating}" : ""}')
              .join('\n')
          : data.restaurants
              .map((r) =>
                  '  ${r.name}: ₹${r.deliveryFee} delivery, ${r.deliveryTime}'
                  '${r.discount.isNotEmpty ? ", ${r.discount}" : ""}')
              .join('\n');
      return '$app:\n$items';
    }).join('\n\n');

    final couponsBlock = activeCoupons.isEmpty
        ? 'None stored'
        : activeCoupons
            .map((c) =>
                '${c.app} ${c.code}: '
                '${c.flatDiscount > 0 ? "₹${c.flatDiscount} off" : "${c.discountPct}% off"} '
                'on min cart ₹${c.minCart}')
            .join(', ');

    final bankBlock = bankCards.isEmpty
        ? 'None specified'
        : bankCards.join(', ');

    final peopleBlock = prefs.numPeople == 1
        ? prefs.peoplePreferences.isNotEmpty
            ? prefs.peoplePreferences.first
            : 'no specific preference'
        : List.generate(prefs.numPeople, (i) {
            final p = i < prefs.peoplePreferences.length
                ? prefs.peoplePreferences[i]
                : 'no preference';
            return 'Person ${i + 1}: $p';
          }).join(', ');

    return '''
[WHAT USER WANTS TODAY]
"$query"
Diet: ${prefs.dietType} | People: ${prefs.numPeople} ($peopleBlock)
Meal: $meal | Budget: ₹$budget | Intent: $signalLabel ($totalMins mins on food apps)
Location: $locationLabel

[LIVE SCRAPED DATA FROM APPS]
$scrapedBlock

[ACTIVE COUPONS]
$couponsBlock
Scraped banners may also contain bank-specific offers — user has these cards: $bankBlock

[ORDER HISTORY]
Frequently orders from: ${topRestaurants.join(', ')}
Avoid (bad rated): ${badRestaurants.join(', ')}

[TASK]
Return a JSON array of up to 10 food items the user should order today based on their query "$query".
Each element must have exactly these fields:
{
  "name": "dish name",
  "restaurant": "restaurant name",
  "platform": "Swiggy" or "Zomato" or "Blinkit",
  "price": integer (base price in rupees),
  "final_price": integer (after coupon + delivery fee),
  "discount": integer (rupees saved by coupon, 0 if none),
  "coupon_code": "CODE" or null,
  "delivery_fee": integer,
  "delivery_time": "25-35 min",
  "rating": "4.2" or "",
  "addon_suggestion": "Add X for ₹Y to unlock COUPON saving ₹Z net" or null,
  "reason": "one short phrase why this is a good pick for them"
}
Sort by best value (lowest final_price, weighted by rating and history match).
If live scraped data is available use those exact prices. If not, use reasonable estimates.
Return ONLY the JSON array. No markdown. No explanation.
''';
  }

  List<FoodItem> _parseFoodItems(
    String raw,
    Map<String, AppLiveData> liveData,
    List<Coupon> activeCoupons,
  ) {
    try {
      // Strip markdown code fences if Claude wrapped it
      var cleaned = raw.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.replaceAll(RegExp(r'```[a-z]*'), '').trim();
      }
      final list = jsonDecode(cleaned) as List<dynamic>;
      return list
          .map((e) => FoodItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .take(10)
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<String> _topRestaurants(List<Order> orders) {
    final counts = <String, int>{};
    for (final o in orders) {
      counts[o.restaurant] = (counts[o.restaurant] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).map((e) => e.key).toList();
  }
}
