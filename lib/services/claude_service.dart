import '../models/coupon.dart';
import '../models/order.dart';
import '../models/preference.dart';
import 'llm_service.dart';
import 'rule_engine.dart';

const _systemPrompt =
    'You are a personal food ordering agent. Be concise. '
    'One recommendation. Show true final price always. '
    'Never suggest items the user dislikes.';

class ClaudeService {
  final RuleEngine _ruleEngine;
  final LlmService _llm;

  ClaudeService(this._ruleEngine) : _llm = LlmService();

  // True when the active provider has a key — used to decide AI vs Static mode.
  Future<bool> hasApiKey() => LlmService.hasActiveKey();

  Future<String> getRecommendation({
    required Preference prefs,
    required List<Order> recentOrders,
    required List<Coupon> activeCoupons,
    required List<String> badRestaurants,
    required int totalFoodAppMins,
    required String locationLabel,
    required Map<String, int> cartEstimates,
    required Map<String, int> deliveryFees,
    required Map<String, int> platformFees,
    Map<String, List<String>> liveBanners = const {},
    List<String> liveCouponCodes = const [],
  }) async {
    final signal = _ruleEngine.scoreIntent(totalFoodAppMins);
    final signalLabel = _ruleEngine.intentLabel(signal);
    final meal = _ruleEngine.mealType();
    final budget = _ruleEngine.maxBudget(prefs);

    final deals = <DealResult>[];
    for (final app in ['Swiggy', 'Zomato', 'Blinkit']) {
      deals.add(_ruleEngine.bestDeal(
        app: app,
        baseCart: cartEstimates[app] ?? 300,
        deliveryFee: deliveryFees[app] ?? 40,
        platformFee: platformFees[app] ?? 10,
        coupons: activeCoupons.where((c) => c.app == app).toList(),
        okAddons: prefs.okAddons,
      ));
    }
    final ranked = _ruleEngine.rankDeals(deals);

    final userPrompt = _buildPrompt(
      prefs: prefs,
      meal: meal,
      budget: budget,
      signalLabel: signalLabel,
      totalMins: totalFoodAppMins,
      locationLabel: locationLabel,
      ranked: ranked,
      topCuisines: _topCuisines(recentOrders),
      recentRestaurants:
          recentOrders.take(5).map((o) => o.restaurant).toSet().toList(),
      badRestaurants: badRestaurants,
      signal: signal,
      liveBanners: liveBanners,
      liveCouponCodes: liveCouponCodes,
    );

    return _llm.complete(_systemPrompt, userPrompt);
  }

  String _buildPrompt({
    required Preference prefs,
    required String meal,
    required int budget,
    required String signalLabel,
    required int totalMins,
    required String locationLabel,
    required List<DealResult> ranked,
    required List<String> topCuisines,
    required List<String> recentRestaurants,
    required List<String> badRestaurants,
    required IntentSignal signal,
    Map<String, List<String>> liveBanners = const {},
    List<String> liveCouponCodes = const [],
  }) {
    final dealsBlock = ranked.map((d) {
      final couponInfo = d.bestCoupon != null
          ? 'coupon ${d.bestCoupon!.code} saves ₹${d.discount}'
          : 'no coupon';
      final addon = d.addonSuggestion != null ? ' | ${d.addonSuggestion}' : '';
      return '  ${d.app}: ₹${d.finalPrice} final ($couponInfo)$addon';
    }).join('\n');

    final taskInstruction = signal == IntentSignal.decisionFatigue
        ? 'User is fatigued. Give ONE clear option only, no alternatives.'
        : signal == IntentSignal.lowIntent
            ? 'User may not be ordering. Be passive, just surface the best deal briefly.'
            : 'Recommend the best deal. Show savings vs second-best option.';

    return '''
[USER PREFERENCES]
Diet: ${prefs.dietType}
Favourite cuisines: ${prefs.favCuisines.join(', ')}
Avoid items: ${prefs.avoidItems.join(', ')}
Budget for $meal: ₹$budget
OK add-ons: ${prefs.okAddons.join(', ')}
Payment methods: ${prefs.paymentMethods.join(', ')}

[TODAY BEHAVIOUR]
Time: $meal | Intent signal: $signalLabel ($totalMins mins on food apps today)
Delivery location: $locationLabel

[AVAILABLE DEALS]
$dealsBlock

[ORDER HISTORY SIGNAL]
Top cuisines ordered: ${topCuisines.join(', ')}
Recently visited: ${recentRestaurants.join(', ')}
Bad-rated restaurants to avoid: ${badRestaurants.join(', ')}

[LIVE SCREEN DATA]
${liveBanners.isEmpty ? 'No live data available.' : liveBanners.entries.map((e) => '${e.key} banners: ${e.value.join(" | ")}').join('\n')}
${liveCouponCodes.isEmpty ? '' : 'Spotted coupon codes: ${liveCouponCodes.join(', ')}'}

[TASK]
$taskInstruction
Show true final price. Max 3 sentences.
''';
  }

  List<String> _topCuisines(List<Order> orders) {
    final counts = <String, int>{};
    for (final o in orders) {
      counts[o.restaurant] = (counts[o.restaurant] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(3).map((e) => e.key).toList();
  }
}
