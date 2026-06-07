import 'dart:convert';

import '../models/coupon.dart';
import '../models/food_item.dart';
import '../models/order.dart';

enum IntentSignal { lowIntent, mediumIntent, highIntent, decisionFatigue }

/// A live offer scraped from the app screen right now (not from history / DB).
/// Examples it represents: "40% OFF UPTO ₹80 ABOVE ₹179", "FLAT ₹125 OFF",
/// "Free Del + Extra 10% off above ₹1200".
class LiveOffer {
  final int pct;          // percentage off (0 if flat-only)
  final int flatAmount;   // flat ₹ off (0 if pct-only)
  final int capAmount;    // max ₹ discount (0 = uncapped)
  final int minCart;      // minimum cart value to qualify (0 = none)
  final bool freeDelivery;
  final String label;     // concise display label

  const LiveOffer({
    this.pct = 0,
    this.flatAmount = 0,
    this.capAmount = 0,
    this.minCart = 0,
    this.freeDelivery = false,
    required this.label,
  });

  /// Discount this offer gives on an item of [price] (0 if below min-cart).
  int discountFor(int price) {
    if (price < minCart) return 0;
    if (flatAmount > 0) return flatAmount.clamp(0, price);
    if (pct > 0) {
      final raw = (price * pct / 100).round();
      final capped = capAmount > 0 ? raw.clamp(0, capAmount) : raw;
      return capped.clamp(0, price);
    }
    return 0;
  }
}

/// Full price breakdown for one item. The all-in price mirrors what Swiggy
/// actually charges at checkout: item − offer + packaging + platform fee +
/// restaurant GST + delivery. Packaging/platform/GST are ESTIMATES — the exact
/// paise only exist on the cart page, which we don't open (read-only).
class PriceBreakdown {
  final int itemPrice;
  final int discount;
  final int packaging;
  final int deliveryFee;
  final int gst;
  final int platformFee;
  final int finalPrice;
  const PriceBreakdown({
    required this.itemPrice,
    required this.discount,
    required this.packaging,
    required this.deliveryFee,
    required this.gst,
    required this.platformFee,
    required this.finalPrice,
  });
}

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

  // Derives a sensible budget from average spend in order history.
  // Falls back to ₹400 when there is no history yet.
  int maxBudget(List<Order> recentOrders) {
    if (recentOrders.isEmpty) return 400;
    final avg = recentOrders.map((o) => o.totalPaid).reduce((a, b) => a + b) ~/
        recentOrders.length;
    return (avg * 1.2).round();
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

  // ── Live offers, price breakdown, diet ─────────────────────────────────────

  /// Parse the offers visible on screen *right now* into structured [LiveOffer]s.
  /// Reads scraped banner/offer fragments — never order history or the DB.
  ///
  /// A single fragment can hold several offers (the carousel peeks the next card),
  /// e.g. "FLAT ₹125 OFF | ABOVE ₹199 FLAT ₹150 OFF | ABOVE ₹249". So we scan the
  /// whole text left-to-right for offer "anchors" ("X% off" / "flat ₹X off") and
  /// pair each with the cap / min-cart that appear before the NEXT anchor — that
  /// keeps every offer matched to its own threshold.
  List<LiveOffer> parseLiveOffers(List<String> banners, List<String> coupons) {
    final capRe = RegExp(r'upto\s*₹\s*(\d+)');
    final aboveRe = RegExp(r'above\s*₹\s*(\d+)');
    final anchorRe = RegExp(r'(\d+)\s*%\s*off|flat\s*₹\s*(\d+)\s*off');

    final text = [...banners, ...coupons].join('  ').toLowerCase();
    final anchors = anchorRe.allMatches(text).toList();

    final offers = <LiveOffer>[];
    final seen = <String>{};
    for (var i = 0; i < anchors.length; i++) {
      final m = anchors[i];
      final segEnd = (i + 1 < anchors.length) ? anchors[i + 1].start : text.length;
      final seg = text.substring(m.end, segEnd); // text up to the next offer
      // Skip payment-conditional offers (require a specific card/bank/wallet/UPI).
      if (_isPaymentConditional(text.substring(m.start, segEnd))) continue;

      final cap = _firstInt(capRe, seg);
      final minCart = _firstInt(aboveRe, seg) ?? 0;
      final pctStr = m.group(1);
      final flatStr = m.group(2);

      final LiveOffer offer;
      if (pctStr != null) {
        final pct = int.parse(pctStr);
        offer = LiveOffer(
          pct: pct,
          capAmount: cap ?? 0,
          minCart: minCart,
          label: cap != null ? '$pct% OFF up to ₹$cap' : '$pct% OFF',
        );
      } else {
        final flat = int.parse(flatStr!);
        offer = LiveOffer(
          flatAmount: flat,
          minCart: minCart,
          label: 'FLAT ₹$flat OFF',
        );
      }
      final key = '${offer.pct}|${offer.flatAmount}|${offer.capAmount}|${offer.minCart}';
      if (seen.add(key)) offers.add(offer);
    }

    if (text.contains('free del')) {
      offers.add(const LiveOffer(freeDelivery: true, label: 'FREE DELIVERY'));
    }
    return offers;
  }

  // True if an offer requires a specific payment method (card/bank/wallet/UPI),
  // i.e. it is NOT a pure price-based coupon.
  static final _paymentWords = RegExp(
    r'credit|debit|\bcard\b|\bcc\b|\bemi\b|bank|wallet|upi|paytm|phonepe|gpay|'
    r'amazon pay|simpl|lazypay|rupay|visa|master|amex|hdfc|icici|axis|sbi|kotak|'
    r'yes bank|rbl|idfc|indusind|onecard|au bank|federal',
  );
  static bool _isPaymentConditional(String t) => _paymentWords.hasMatch(t);

  /// Best live offer for an item of [price] — the one giving the most discount.
  LiveOffer? bestOffer(List<LiveOffer> offers, int price) {
    LiveOffer? best;
    var bestVal = -1;
    for (final o in offers) {
      final v = o.discountFor(price) + (o.freeDelivery ? 1 : 0);
      if (v > bestVal) { bestVal = v; best = o; }
    }
    return best;
  }

  /// Final price = item − live coupon. We deliberately do NOT estimate
  /// packaging / platform fee / GST (those only exist exactly on the cart page,
  /// which we don't open). GST is surfaced to the user as a plain "+ GST" note.
  PriceBreakdown computeBreakdown({
    required int itemPrice,
    required int deliveryFee,
    LiveOffer? offer,
  }) {
    final discount = offer?.discountFor(itemPrice) ?? 0;
    final finalPrice = (itemPrice - discount).clamp(0, itemPrice);
    return PriceBreakdown(
      itemPrice: itemPrice,
      discount: discount,
      packaging: 0,
      deliveryFee: 0,
      gst: 0,
      platformFee: 0,
      finalPrice: finalPrice,
    );
  }

  static int? _firstInt(RegExp re, String s) {
    final m = re.firstMatch(s);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  // Words that clearly mark a dish non-veg. Deliberately excludes ambiguous
  // terms like "tikka"/"tandoori" (paneer tikka is veg).
  static const _nonVegWords = [
    'chicken', 'mutton', 'lamb', 'fish', 'prawn', 'shrimp', 'egg', 'keema',
    'meat', 'bacon', 'ham', 'beef', 'pork', 'seafood', 'non veg', 'non-veg',
  ];
  static const _vegWords = [
    'paneer', 'veg', 'veggie', 'margherita', 'mushroom', 'corn', 'cheese',
    'aloo', 'dal', 'tofu', 'farmhouse', 'capsicum', 'onion', 'tomato',
  ];

  /// true = veg, false = non-veg, null = unknown (from the dish name).
  /// Uses whole-word matching: a plain `contains` wrongly flags "ve**gg**ie" as
  /// non-veg (it contains "egg") and "gra**ham**" as ham.
  static bool? classifyVeg(String name) {
    final n = name.toLowerCase();
    bool hasWord(String w) =>
        RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(n);
    for (final w in _nonVegWords) {
      if (hasWord(w)) return false;
    }
    for (final w in _vegWords) {
      if (hasWord(w)) return true;
    }
    return null;
  }

  // Generic words to ignore when learning item-name keywords from history.
  static const _stopWords = {
    'the', 'and', 'with', 'pizza', 'combo', 'meal', 'regular', 'medium',
    'large', 'small', 'pack', 'piece', 'pieces', 'fresh', 'special', 'classic',
    'new', 'for', 'of', 'in', 'extra',
  };

  /// Ranks scraped items by the user's preference, returning the top [limit]:
  ///  1. diet — vegetarian/vegan drops non-veg; non-vegetarian surfaces non-veg first
  ///  2. order-history affinity — restaurants and dish keywords the user orders often
  ///  3. cheapest all-in price as the tie-breaker
  /// With no history (nothing imported yet) this gracefully falls back to diet + price.
  List<FoodItem> rankByPreference(
    List<FoodItem> items,
    String diet,
    List<Order> history, {
    int limit = 30,
  }) {
    // Learn from history: which restaurants and dish keywords recur.
    final favRestaurants = <String>{};
    final keywordFreq = <String, int>{};
    for (final o in history) {
      if (o.restaurant.isNotEmpty) favRestaurants.add(o.restaurant.toLowerCase());
      for (final dish in _historyItemNames(o.itemsJson)) {
        for (final w in _words(dish)) {
          keywordFreq[w] = (keywordFreq[w] ?? 0) + 1;
        }
      }
    }

    int affinity(FoodItem i) {
      var s = 0;
      if (favRestaurants.contains(i.restaurant.toLowerCase())) s += 5;
      for (final w in _words(i.name)) {
        s += keywordFreq[w] ?? 0;
      }
      return s;
    }

    // Vegetarian/vegan: hard-drop clearly non-veg dishes.
    final pool = (diet == 'vegetarian' || diet == 'vegan')
        ? items.where((i) => i.isVeg != false).toList()
        : items.toList();

    pool.sort((a, b) {
      if (diet == 'non-vegetarian') {
        final av = a.isVeg == false ? 0 : 1; // non-veg first
        final bv = b.isVeg == false ? 0 : 1;
        if (av != bv) return av - bv;
      }
      final aff = affinity(b) - affinity(a); // higher affinity first
      if (aff != 0) return aff;
      return a.finalPrice.compareTo(b.finalPrice);
    });
    return pool.take(limit).toList();
  }

  static List<String> _historyItemNames(String itemsJson) {
    try {
      final decoded = jsonDecode(itemsJson);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return const [];
  }

  static List<String> _words(String s) => s
      .toLowerCase()
      .split(RegExp(r'[^a-z]+'))
      .where((w) => w.length > 2 && !_stopWords.contains(w))
      .toList();

  // Given a cart value and list of coupons, finds the coupon + optional
  // add-on combo that yields the highest net saving.
  DealResult bestDeal({
    required String app,
    required int baseCart,
    required int deliveryFee,
    required int platformFee,
    required List<Coupon> coupons,
    List<String> okAddons = const [],
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
