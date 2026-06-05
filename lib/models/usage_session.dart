class UsageSession {
  final int? id;
  final DateTime date;
  final String app;
  final int totalMins;
  final int openCount;
  final bool orderPlaced;
  final String signal;

  const UsageSession({
    this.id,
    required this.date,
    required this.app,
    required this.totalMins,
    required this.openCount,
    required this.orderPlaced,
    required this.signal,
  });

  factory UsageSession.fromMap(Map<String, dynamic> map) => UsageSession(
        id: map['id'] as int?,
        date: DateTime.parse(map['date'] as String),
        app: map['app'] as String,
        totalMins: map['total_mins'] as int,
        openCount: map['open_count'] as int,
        orderPlaced: (map['order_placed'] as int) == 1,
        signal: map['signal'] as String,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'date': date.toIso8601String().split('T').first,
        'app': app,
        'total_mins': totalMins,
        'open_count': openCount,
        'order_placed': orderPlaced ? 1 : 0,
        'signal': signal,
      };
}
