import 'dart:convert';

class Preference {
  final String dietType; // 'none' | 'vegetarian' | 'vegan' | 'non-vegetarian'
  final int numPeople;
  final List<String> peoplePreferences; // one free-text note per person
  final List<String> bankCards; // e.g. ['HDFC', 'Axis'] — used to match credit-card coupons

  const Preference({
    required this.dietType,
    required this.numPeople,
    required this.peoplePreferences,
    this.bankCards = const [],
  });

  factory Preference.fromMap(Map<String, dynamic> map) => Preference(
        dietType: map['diet_type'] as String,
        numPeople: map['num_people'] as int,
        peoplePreferences: List<String>.from(
            jsonDecode(map['people_prefs'] as String)),
        bankCards: map['bank_cards'] != null
            ? List<String>.from(jsonDecode(map['bank_cards'] as String))
            : [],
      );

  Map<String, dynamic> toMap() => {
        'id': 1,
        'diet_type': dietType,
        'num_people': numPeople,
        'people_prefs': jsonEncode(peoplePreferences),
        'bank_cards': jsonEncode(bankCards),
      };

  Preference copyWith({
    String? dietType,
    int? numPeople,
    List<String>? peoplePreferences,
    List<String>? bankCards,
  }) =>
      Preference(
        dietType: dietType ?? this.dietType,
        numPeople: numPeople ?? this.numPeople,
        peoplePreferences: peoplePreferences ?? this.peoplePreferences,
        bankCards: bankCards ?? this.bankCards,
      );
}
