import 'package:flutter/material.dart';
import '../services/rule_engine.dart';

class IntentIndicator extends StatelessWidget {
  final IntentSignal signal;
  final int totalMins;

  const IntentIndicator({super.key, required this.signal, required this.totalMins});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (signal) {
      IntentSignal.lowIntent => ('Just browsing', Colors.grey, Icons.visibility_outlined),
      IntentSignal.mediumIntent => ('Thinking about ordering', Colors.blue, Icons.search),
      IntentSignal.highIntent => ('Ready to order', Colors.green, Icons.restaurant),
      IntentSignal.decisionFatigue => ('Decision fatigue', Colors.orange, Icons.psychology_outlined),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        const SizedBox(width: 4),
        Text('· ${totalMins}m today',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ],
    );
  }
}
