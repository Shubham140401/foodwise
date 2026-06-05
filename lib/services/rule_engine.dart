import '../models/coupon.dart';
import '../models/preference.dart';

enum IntentSignal { lowIntent, mediumIntent, highIntent, decisionFatigue }

class DealResult {
  final String app;
  final Coupon? bestCoupon;
  final int baseCart;
  final int addonCost;
  final int discount;
  final int deliveryFee;
  final int platformFee;
  final int finalPrice;
  final String? addonSuggestion;
  final int saving;

  const DealResult({
    required this.app,
    this.bestCoupon,
    required this.baseCart,
    required this.addonCost,
    required this.discount,
    required this.deliveryFee,
    required this.platformFee,
    required this.finalPrice,
    this.addonSuggestion,
    required this.saving,
  });
}

class RuleEngine {
  IntentSignal scoreIntent(int totalMinsToday) {
    if (totalMinsToday <= 3) return IntentSignal.lowIntent;
    if (totalMinsToday <= 8) return IntentSignal.mediumIntent;
    if (totalMinsToday <= 15) return IntentSignal.highIntent;
    return IntentSignal.decisionFatigue;
  }

  String intentLabel(IntentSignal signal) {
    switch (signal) {
      case IntentSignal.lowIntent:
        return 'low_intent';
      case IntentSignal.mediumIntent:
        return 'medium_intent';
      case IntentSignal.highIntent:
        return 'high_intent';
      case IntentSignal.decisionFatigue:
        return 'decision_fatigue';
    }
  }

  String mealType() {
    final hour = DateTime.now().hour;
    if (hour >= 11 && hour < 16) return 'lunch';
    if (hour >= 19 && hour < 23) return 'dinner';
    return 'late_night';
  }

  int maxBudget(Preference pref) {
    final meal = mealType();
    if (meal == 'lunch') return pref.maxSpendLunch;
    return pref.maxSpendDinner;
  }

  // Calculates actual discount amount for a coupon given cart value.
  int calcDiscount(Coupon coupon, int cartValue) {
    if (cartValue < coupon.minCart) return 0;
    if (coupon.flatDiscount > 0) return coupon.flatDiscount;
    if (coupon.discountPct > 0) {
      final raw = (cartValue * coupon.discountPct / 100).round();
      return coupon.maxDiscount > 0 ? raw.clamp(0, coupon.maxDiscount) : raw;
    }
    return 0;
  }

  // Given a cart value and list of coupons, finds the coupon + optional
  // add-on combo that yields the highest net saving.
  DealResult bestDeal({
    required String app,
    required int baseCart,
    required int deliveryFee,
    required int platformFee,
    required List<Coupon> coupons,
    required List<String> okAddons,
    int addonUnitCost = 50,
  }) {
    DealResult? best;

    for (final coupon in coupons) {
      if (coupon.isExpired) continue;

      // Try without add-on first
      final discountDirect = calcDiscount(coupon, baseCart);
      final finalDirect = baseCart + deliveryFee + platformFee - discountDirect;
      final savingDirect = discountDirect;

      final candidate = DealResult(
        app: app,
        bestCoupon: coupon,
        baseCart: baseCart,
        addonCost: 0,
        discount: discountDirect,
        deliveryFee: deliveryFee,
        platformFee: platformFee,
        finalPrice: finalDirect,
        saving: savingDirect,
      );

      if (best == null || candidate.saving > best.saving) best = candidate;

      // Try adding one cheap add-on to hit minCart threshold if just below
      if (coupon.minCart > 0 && baseCart < coupon.minCart && okAddons.isNotEmpty) {
        final needed = coupon.minCart - baseCart;
        if (needed <= addonUnitCost * 3) {
          final addons = ((needed / addonUnitCost).ceil());
          final addonCost = addons * addonUnitCost;
          final newCart = baseCart + addonCost;
          final discountWithAddon = calcDiscount(coupon, newCart);
          final finalWithAddon = newCart + deliveryFee + platformFee - discountWithAddon;
          final savingWithAddon = discountWithAddon - addonCost;

          if (savingWithAddon > 0) {
            final withAddon = DealResult(
              app: app,
              bestCoupon: coupon,
              baseCart: baseCart,
              addonCost: addonCost,
              discount: discountWithAddon,
              deliveryFee: deliveryFee,
              platformFee: platformFee,
              finalPrice: finalWithAddon,
              addonSuggestion: 'Add ${okAddons.first} (+₹$addonCost) to unlock coupon',
              saving: savingWithAddon,
            );
            if (withAddon.saving > best.saving) best = withAddon;
          }
        }
      }
    }

    // No valid coupon — return plain price
    if (best != null) return best;
    return DealResult(
          app: app,
          baseCart: baseCart,
          addonCost: 0,
          discount: 0,
          deliveryFee: deliveryFee,
          platformFee: platformFee,
          finalPrice: baseCart + deliveryFee + platformFee,
          saving: 0,
        );
  }

  // Ranks deal results by final price ascending.
  List<DealResult> rankDeals(List<DealResult> deals) {
    final sorted = List<DealResult>.from(deals);
    sorted.sort((a, b) => a.finalPrice.compareTo(b.finalPrice));
    return sorted;
  }

  // Builds a natural-language recommendation WITHOUT any LLM — pure Dart.
  // Used when the user runs the app in static mode (no Claude API key).
  // Mirrors the structure of the Claude prompt's [TASK]: one recommendation,
  // true final price, savings vs second-best, intent-aware tone.
  String staticRecommendation({
    required List<DealResult> ranked,
    required IntentSignal signal,
    required String meal,
    required int budget,
    String? favRestaurant,
  }) {
    if (ranked.isEmpty) {
      return 'No deals to compare yet. Open Swiggy or Zomato so foodwise can '
          'read live prices, or add a coupon in Settings.';
    }

    final best = ranked.first;
    final buf = StringBuffer();

    buf.write('Best value right now: ${best.app} at ₹${best.finalPrice}');
    if (best.bestCoupon != null && best.discount > 0) {
      buf.write(' (coupon ${best.bestCoupon!.code} saves ₹${best.discount})');
    }
    buf.write('.');

    // Savings vs second-best — skip when fatigued (one option only).
    if (ranked.length > 1 && signal != IntentSignal.decisionFatigue) {
      final second = ranked[1];
      final gap = second.finalPrice - best.finalPrice;
      if (gap > 0) {
        buf.write(' That is ₹$gap cheaper than ${second.app} '
            '(₹${second.finalPrice}).');
      } else {
        buf.write(' ${second.app} matches it at ₹${second.finalPrice}.');
      }
    }

    if (best.finalPrice > budget) {
      buf.write(' Note: ₹${best.finalPrice - budget} over your $meal budget '
          'of ₹$budget.');
    }

    if (best.addonSuggestion != null && signal != IntentSignal.decisionFatigue) {
      buf.write(' Tip: ${best.addonSuggestion}.');
    }

    switch (signal) {
      case IntentSignal.decisionFatigue:
        buf.write(' You have been browsing a while — just go with ${best.app} '
            'and skip the comparison.');
        break;
      case IntentSignal.lowIntent:
        break; // keep it brief
      case IntentSignal.mediumIntent:
      case IntentSignal.highIntent:
        if (favRestaurant != null && favRestaurant.isNotEmpty) {
          buf.write(' You order from $favRestaurant a lot — check if it is '
              'cheaper on ${best.app} today.');
        }
        break;
    }

    return buf.toString();
  }
}
