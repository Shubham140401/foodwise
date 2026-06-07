import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/orders_dao.dart';
import '../models/order.dart';


class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<Order>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _ordersFuture = context.read<OrdersDao>().getRecent(limit: 50);
  }

  int _totalSaved(List<Order> orders) =>
      orders.fold(0, (sum, o) => sum + o.discount);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Order history')),
      body: FutureBuilder<List<Order>>(
        future: _ordersFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final orders = snap.data ?? [];
          if (orders.isEmpty) {
            return const Center(child: Text('No orders yet.'));
          }
          final saved = _totalSaved(orders);
          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: theme.colorScheme.primaryContainer,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('${orders.length}', 'Orders'),
                    _stat('₹$saved', 'Total saved'),
                    _stat(
                        orders.isNotEmpty
                            ? '₹${(saved / orders.length).round()}'
                            : '₹0',
                        'Avg saving'),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: orders.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (_, i) => _OrderTile(order: orders[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _stat(String value, String label) => Column(
        children: [
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _OrderTile extends StatefulWidget {
  final Order order;
  const _OrderTile({required this.order});

  @override
  State<_OrderTile> createState() => _OrderTileState();
}

class _OrderTileState extends State<_OrderTile> {
  late int? _rating;

  @override
  void initState() {
    super.initState();
    _rating = widget.order.myRating;
  }

  Future<void> _setRating(int stars) async {
    await context.read<OrdersDao>().updateRating(widget.order.orderId, stars);
    if (mounted) setState(() => _rating = stars);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.secondaryContainer,
            child: Text(
              widget.order.app[0],
              style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.order.restaurant,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  '${widget.order.app} · ${widget.order.mealType} · ₹${widget.order.totalPaid}'
                  '${widget.order.discount > 0 ? "  -₹${widget.order.discount}" : ""}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                // Star rating row
                Row(
                  children: List.generate(5, (i) {
                    final star = i + 1;
                    return GestureDetector(
                      onTap: () => _setRating(star),
                      child: Icon(
                        (_rating != null && star <= _rating!)
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 20,
                        color: (_rating != null && star <= _rating!)
                            ? Colors.amber.shade600
                            : theme.colorScheme.outlineVariant,
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
