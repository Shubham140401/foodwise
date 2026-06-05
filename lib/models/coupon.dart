class Coupon {
  final int? id;
  final String app;
  final String code;
  final int discountPct;
  final int flatDiscount;
  final int minCart;
  final int maxDiscount;
  final DateTime expiresAt;
  final String? paymentReq;
  final bool oneTime;

  const Coupon({
    this.id,
    required this.app,
    required this.code,
    required this.discountPct,
    required this.flatDiscount,
    required this.minCart,
    required this.maxDiscount,
    required this.expiresAt,
    this.paymentReq,
    required this.oneTime,
  });

  factory Coupon.fromMap(Map<String, dynamic> map) => Coupon(
        id: map['id'] as int?,
        app: map['app'] as String,
        code: map['code'] as String,
        discountPct: map['discount_pct'] as int,
        flatDiscount: map['flat_discount'] as int,
        minCart: map['min_cart'] as int,
        maxDiscount: map['max_discount'] as int,
        expiresAt: DateTime.parse(map['expires_at'] as String),
        paymentReq: map['payment_req'] as String?,
        oneTime: (map['one_time'] as int) == 1,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'app': app,
        'code': code,
        'discount_pct': discountPct,
        'flat_discount': flatDiscount,
        'min_cart': minCart,
        'max_discount': maxDiscount,
        'expires_at': expiresAt.toIso8601String(),
        'payment_req': paymentReq,
        'one_time': oneTime ? 1 : 0,
      };

  bool get isExpired => expiresAt.isBefore(DateTime.now());
}
