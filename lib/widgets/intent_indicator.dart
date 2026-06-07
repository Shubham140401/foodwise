import 'package:flutter/material.dart';
import '../services/rule_engine.dart';

class IntentIndicator extends StatelessWidget {
  final IntentSignal signal;
  final int totalMins;

  const IntentIndicator({super.key, required this.signal, required this.totalMins});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (signal) {
      IntentSignal.lowIntent => (
          'Browsing · ${totalMins}m on food apps',
          Colors.grey.shade500,
          Icons.visibility_outlined,
        ),
      IntentSignal.mediumIntent => (
          'Active on food apps · showing best deals',
          Colors.blue.shade600,
          Icons.search,
        ),
      IntentSignal.highIntent => (
          'Ready to order · ranked by best value',
          Colors.green.shade600,
          Icons.restaurant,
        ),
      IntentSignal.decisionFatigue => (
          '${totalMins}m browsing · ranked by best value',
          Colors.orange.shade700,
          Icons.psychology_outlined,
        ),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
