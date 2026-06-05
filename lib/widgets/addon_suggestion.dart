import 'package:flutter/material.dart';

class AddonSuggestion extends StatelessWidget {
  final String suggestion;

  const AddonSuggestion({super.key, required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.add_shopping_cart, color: Colors.amber.shade800, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(suggestion,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.amber.shade900)),
          ),
        ],
      ),
    );
  }
}
