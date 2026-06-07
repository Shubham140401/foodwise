import 'package:flutter/material.dart';

import '../models/food_item.dart';

class FoodItemCard extends StatelessWidget {
  final FoodItem item;
  final int rank;

  const FoodItemCard({super.key, required this.item, required this.rank});

  Color _platformColor(String platform) {
    switch (platform) {
      case 'Zomato':
        return const Color(0xFFE23744);
      case 'Blinkit':
        return const Color(0xFFF8D62B);
      default:
        return const Color(0xFFFC8019); // Swiggy orange
    }
  }

  // Final price = item − live coupon. GST is shown as plain text only (we don't
  // estimate it — exact charges live on the cart page, which we don't open).
  String _breakdown(FoodItem item) {
    final b = StringBuffer();
    if (item.originalPrice > item.price) {
      b.write('₹${item.originalPrice} → ₹${item.price} menu'); // restaurant's own deal
    } else {
      b.write('₹${item.price}');
    }
    if (item.discount > 0) b.write('  −₹${item.discount} coupon');
    b.write('  =  ₹${item.finalPrice}  + GST');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platformColor = _platformColor(item.platform);
    final hasCoupon = item.discount > 0 && item.couponCode != null;
    // Strike the menu's original price when the item is discounted (menu deal
    // and/or coupon brought the final price below it).
    final struckPrice = item.originalPrice > item.finalPrice
        ? item.originalPrice
        : (hasCoupon ? item.price : 0);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: rank + food name + platform badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rank == 1
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$rank',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: rank == 1
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item.isVeg != null) ...[
                            _VegMarker(isVeg: item.isVeg!),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              item.name,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      if (item.restaurant.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.restaurant,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                // Platform badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: platformColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: platformColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    item.platform,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: platformColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Price row
            Row(
              children: [
                if (struckPrice > 0) ...[
                  Text(
                    '₹$struckPrice',
                    style: theme.textTheme.bodySmall?.copyWith(
                      decoration: TextDecoration.lineThrough,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  '₹${item.finalPrice}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (hasCoupon) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${item.couponCode} −₹${item.discount}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                // Delivery info
                if (item.deliveryTime.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.schedule_outlined,
                          size: 13,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text(
                        item.deliveryTime,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                if (item.deliveryFee > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '+₹${item.deliveryFee} delivery',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),

            // All-in price breakdown: item − coupon + delivery + GST + fee
            const SizedBox(height: 6),
            Text(
              _breakdown(item),
              style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),

            // Rating
            if (item.rating.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.star_rounded,
                      size: 13, color: Colors.amber.shade600),
                  const SizedBox(width: 2),
                  Text(
                    item.rating,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],

            // Why recommended
            if (item.reason != null && item.reason!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                item.reason!,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontStyle: FontStyle.italic),
              ),
            ],

            // Add-on suggestion
            if (item.addonSuggestion != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.tips_and_updates_outlined,
                        size: 13, color: Colors.amber.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.addonSuggestion!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// The classic veg (green) / non-veg (red) square marker.
class _VegMarker extends StatelessWidget {
  final bool isVeg;
  const _VegMarker({required this.isVeg});

  @override
  Widget build(BuildContext context) {
    final color = isVeg ? Colors.green.shade700 : Colors.red.shade700;
    return Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
