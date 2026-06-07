class FoodItem {
  final String name;
  final String restaurant;
  final String platform; // 'Swiggy' | 'Zomato' | 'Blinkit'
  final int price;        // effective (discounted) menu price
  final int originalPrice; // struck-out menu price, or == price if not discounted
  final int finalPrice;   // price − live cart coupon (GST shown as text, not added)
  final int discount;
  final String? couponCode; // live offer label (e.g. "40% OFF", "FLAT ₹80")
  final int deliveryFee;
  final int packaging;    // estimated restaurant packaging charge
  final int gst;          // estimated restaurant GST
  final int platformFee;  // estimated platform fee
  final String deliveryTime;
  final String rating;
  final bool? isVeg;      // true=veg, false=non-veg, null=unknown
  final String? addonSuggestion;
  final String? reason; // why this is recommended

  const FoodItem({
    required this.name,
    required this.restaurant,
    required this.platform,
    required this.price,
    this.originalPrice = 0,
    required this.finalPrice,
    required this.discount,
    this.couponCode,
    required this.deliveryFee,
    this.packaging = 0,
    this.gst = 0,
    this.platformFee = 0,
    required this.deliveryTime,
    required this.rating,
    this.isVeg,
    this.addonSuggestion,
    this.reason,
  });

  // Saving = the discount the live coupon/offer knocks off the item.
  int get saving => discount;

  factory FoodItem.fromMap(Map<String, dynamic> map) => FoodItem(
        name: map['name'] as String? ?? 'Unknown',
        restaurant: map['restaurant'] as String? ?? '',
        platform: map['platform'] as String? ?? 'Swiggy',
        price: (map['price'] as num?)?.toInt() ?? 0,
        originalPrice: (map['original_price'] as num?)?.toInt() ?? 0,
        finalPrice: (map['final_price'] as num?)?.toInt() ??
            (map['price'] as num?)?.toInt() ?? 0,
        discount: (map['discount'] as num?)?.toInt() ?? 0,
        couponCode: map['coupon_code'] as String?,
        deliveryFee: (map['delivery_fee'] as num?)?.toInt() ?? 0,
        packaging: (map['packaging'] as num?)?.toInt() ?? 0,
        gst: (map['gst'] as num?)?.toInt() ?? 0,
        platformFee: (map['platform_fee'] as num?)?.toInt() ?? 0,
        deliveryTime: map['delivery_time'] as String? ?? '',
        rating: map['rating'] as String? ?? '',
        isVeg: map['is_veg'] as bool?,
        addonSuggestion: map['addon_suggestion'] as String?,
        reason: map['reason'] as String?,
      );
}
