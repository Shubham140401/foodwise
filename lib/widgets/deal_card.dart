import 'package:flutter/material.dart';
import '../services/rule_engine.dart';

class DealCard extends StatelessWidget {
  final DealResult deal;
  final bool isTop;

  const DealCard({super.key, required this.deal, this.isTop = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: isTop ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isTop
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(deal.app,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (isTop)
                  Chip(
                    label: const Text('Best deal'),
                    backgroundColor: theme.colorScheme.primaryContainer,
                    labelStyle: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontSize: 11),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('₹${deal.finalPrice}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary)),
                const SizedBox(width: 8),
                if (deal.discount > 0)
                  Text('saves ₹${deal.discount}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.green.shade700)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Cart ₹${deal.baseCart} + delivery ₹${deal.deliveryFee} + fee ₹${deal.platformFee}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            if (deal.bestCoupon != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.local_offer_outlined,
                      size: 14, color: Colors.green.shade700),
                  const SizedBox(width: 4),
                  Text(deal.bestCoupon!.code,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.green.shade700)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
