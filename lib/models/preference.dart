import 'dart:convert';

class Preference {
  final String dietType;
  final List<String> favCuisines;
  final List<String> avoidItems;
  final int maxSpendLunch;
  final int maxSpendDinner;
  final List<String> okAddons;
  final List<String> paymentMethods;
  final String? homeAddress;
  final String? workAddress;

  const Preference({
    required this.dietType,
    required this.favCuisines,
    required this.avoidItems,
    required this.maxSpendLunch,
    required this.maxSpendDinner,
    required this.okAddons,
    required this.paymentMethods,
    this.homeAddress,
    this.workAddress,
  });

  factory Preference.fromMap(Map<String, dynamic> map) => Preference(
        dietType: map['diet_type'] as String,
        favCuisines: List<String>.from(jsonDecode(map['fav_cuisines'] as String)),
        avoidItems: List<String>.from(jsonDecode(map['avoid_items'] as String)),
        maxSpendLunch: map['max_spend_lunch'] as int,
        maxSpendDinner: map['max_spend_dinner'] as int,
        okAddons: List<String>.from(jsonDecode(map['ok_addons'] as String)),
        paymentMethods: List<String>.from(jsonDecode(map['payment_methods'] as String)),
        homeAddress: map['home_address'] as String?,
        workAddress: map['work_address'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': 1,
        'diet_type': dietType,
        'fav_cuisines': jsonEncode(favCuisines),
        'avoid_items': jsonEncode(avoidItems),
        'max_spend_lunch': maxSpendLunch,
        'max_spend_dinner': maxSpendDinner,
        'ok_addons': jsonEncode(okAddons),
        'payment_methods': jsonEncode(paymentMethods),
        'home_address': homeAddress,
        'work_address': workAddress,
      };

  Preference copyWith({
    String? dietType,
    List<String>? favCuisines,
    List<String>? avoidItems,
    int? maxSpendLunch,
    int? maxSpendDinner,
    List<String>? okAddons,
    List<String>? paymentMethods,
    String? homeAddress,
    String? workAddress,
  }) =>
      Preference(
        dietType: dietType ?? this.dietType,
        favCuisines: favCuisines ?? this.favCuisines,
        avoidItems: avoidItems ?? this.avoidItems,
        maxSpendLunch: maxSpendLunch ?? this.maxSpendLunch,
        maxSpendDinner: maxSpendDinner ?? this.maxSpendDinner,
        okAddons: okAddons ?? this.okAddons,
        paymentMethods: paymentMethods ?? this.paymentMethods,
        homeAddress: homeAddress ?? this.homeAddress,
        workAddress: workAddress ?? this.workAddress,
      );
}
