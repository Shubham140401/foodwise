class FeedbackEntry {
  final String orderId;
  final bool followedAgent;
  final String satisfaction;
  final bool agentWasRight;
  final DateTime ratedAt;

  const FeedbackEntry({
    required this.orderId,
    required this.followedAgent,
    required this.satisfaction,
    required this.agentWasRight,
    required this.ratedAt,
  });

  factory FeedbackEntry.fromMap(Map<String, dynamic> map) => FeedbackEntry(
        orderId: map['order_id'] as String,
        followedAgent: (map['followed_agent'] as int) == 1,
        satisfaction: map['satisfaction'] as String,
        agentWasRight: (map['agent_was_right'] as int) == 1,
        ratedAt: DateTime.parse(map['rated_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'order_id': orderId,
        'followed_agent': followedAgent ? 1 : 0,
        'satisfaction': satisfaction,
        'agent_was_right': agentWasRight ? 1 : 0,
        'rated_at': ratedAt.toIso8601String(),
      };
}
