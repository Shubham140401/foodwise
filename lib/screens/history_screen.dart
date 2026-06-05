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

class _OrderTile extends StatelessWidget {
  final Order order;
  const _OrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        child: Text(order.app[0],
            style: TextStyle(color: theme.colorScheme.onSecondaryContainer)),
      ),
      title: Text(order.restaurant),
      subtitle: Text('${order.app} · ${order.mealType} · ₹${order.totalPaid}'),
      trailing: order.discount > 0
          ? Text('-₹${order.discount}',
              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
          : null,
    );
  }
}
