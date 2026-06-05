class Order {
  final String orderId;
  final String app;
  final String restaurant;
  final String itemsJson;
  final int subtotal;
  final int deliveryFee;
  final int platformFee;
  final String? couponUsed;
  final int discount;
  final int totalPaid;
  final int? myRating;
  final DateTime orderedAt;
  final String mealType;

  const Order({
    required this.orderId,
    required this.app,
    required this.restaurant,
    required this.itemsJson,
    required this.subtotal,
    required this.deliveryFee,
    required this.platformFee,
    this.couponUsed,
    required this.discount,
    required this.totalPaid,
    this.myRating,
    required this.orderedAt,
    required this.mealType,
  });

  factory Order.fromMap(Map<String, dynamic> map) => Order(
        orderId: map['order_id'] as String,
        app: map['app'] as String,
        restaurant: map['restaurant'] as String,
        itemsJson: map['items_json'] as String,
        subtotal: map['subtotal'] as int,
        deliveryFee: map['delivery_fee'] as int,
        platformFee: map['platform_fee'] as int,
        couponUsed: map['coupon_used'] as String?,
        discount: map['discount'] as int,
        totalPaid: map['total_paid'] as int,
        myRating: map['my_rating'] as int?,
        orderedAt: DateTime.parse(map['ordered_at'] as String),
        mealType: map['meal_type'] as String,
      );

  Map<String, dynamic> toMap() => {
        'order_id': orderId,
        'app': app,
        'restaurant': restaurant,
        'items_json': itemsJson,
        'subtotal': subtotal,
        'delivery_fee': deliveryFee,
        'platform_fee': platformFee,
        'coupon_used': couponUsed,
        'discount': discount,
        'total_paid': totalPaid,
        'my_rating': myRating,
        'ordered_at': orderedAt.toIso8601String(),
        'meal_type': mealType,
      };
}
