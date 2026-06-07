import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/coupons_dao.dart';
import '../models/coupon.dart';

class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});

  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen> {
  late Future<List<Coupon>> _couponsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _couponsFuture = context.read<CouponsDao>().getActive();
    if (mounted) setState(() {});
  }

  Future<void> _delete(int id) async {
    await context.read<CouponsDao>().delete(id);
    _reload();
  }

  Future<void> _showAddSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AddCouponSheet(),
    );
    if (added == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Coupons')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        icon: const Icon(Icons.add),
        label: const Text('Add coupon'),
      ),
      body: FutureBuilder<List<Coupon>>(
        future: _couponsFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final coupons = snap.data ?? [];
          if (coupons.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.discount_outlined,
                        size: 48, color: theme.colorScheme.outlineVariant),
                    const SizedBox(height: 12),
                    const Text('No active coupons'),
                    const SizedBox(height: 6),
                    Text(
                      'Add codes from promo emails or SMS.\nfoodwise also auto-reads coupons while scraping.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: coupons.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _CouponCard(
              coupon: coupons[i],
              onDelete: () => _delete(coupons[i].id!),
            ),
          );
        },
      ),
    );
  }
}

class _CouponCard extends StatelessWidget {
  final Coupon coupon;
  final VoidCallback onDelete;
  const _CouponCard({required this.coupon, required this.onDelete});

  String get _discountLabel => coupon.flatDiscount > 0
      ? '₹${coupon.flatDiscount} off'
      : '${coupon.discountPct}% off';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(coupon.code,
                style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${coupon.app} · $_discountLabel'
                  '${coupon.minCart > 0 ? " on ₹${coupon.minCart}+" : ""}',
                  style: theme.textTheme.bodyMedium,
                ),
                if (coupon.paymentReq != null && coupon.paymentReq!.isNotEmpty)
                  Text(coupon.paymentReq!,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                Text(
                  'Expires ${_formatDate(coupon.expiresAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: coupon.expiresAt
                              .isBefore(DateTime.now().add(const Duration(days: 3)))
                          ? Colors.orange.shade700
                          : theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: theme.colorScheme.error,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}';
}

class _AddCouponSheet extends StatefulWidget {
  const _AddCouponSheet();

  @override
  State<_AddCouponSheet> createState() => _AddCouponSheetState();
}

class _AddCouponSheetState extends State<_AddCouponSheet> {
  final _codeCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _minCartCtrl = TextEditingController();
  final _maxDiscCtrl = TextEditingController();
  final _paymentCtrl = TextEditingController();

  String _app = 'Swiggy';
  bool _isFlat = true;
  DateTime _expiresAt = DateTime.now().add(const Duration(days: 30));
  bool _saving = false;

  static const _apps = ['Swiggy', 'Zomato', 'Blinkit'];

  @override
  void dispose() {
    _codeCtrl.dispose();
    _amountCtrl.dispose();
    _minCartCtrl.dispose();
    _maxDiscCtrl.dispose();
    _paymentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _expiresAt = picked);
  }

  Future<void> _save() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    final amount = int.tryParse(_amountCtrl.text.trim()) ?? 0;

    setState(() => _saving = true);
    final coupon = Coupon(
      app: _app,
      code: code,
      discountPct: _isFlat ? 0 : amount,
      flatDiscount: _isFlat ? amount : 0,
      minCart: int.tryParse(_minCartCtrl.text.trim()) ?? 0,
      maxDiscount: int.tryParse(_maxDiscCtrl.text.trim()) ?? 0,
      expiresAt: _expiresAt,
      paymentReq: _paymentCtrl.text.trim().isEmpty ? null : _paymentCtrl.text.trim(),
      oneTime: false,
    );
    await context.read<CouponsDao>().insert(coupon);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Add coupon', style: theme.textTheme.titleMedium),
            const Spacer(),
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _app,
                decoration: const InputDecoration(
                    labelText: 'App', border: OutlineInputBorder(), isDense: true),
                items: _apps
                    .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                    .toList(),
                onChanged: (v) { if (v != null) setState(() => _app = v); },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _codeCtrl,
                decoration: const InputDecoration(
                    labelText: 'Code *', border: OutlineInputBorder(), isDense: true),
                textCapitalization: TextCapitalization.characters,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('₹ Flat')),
                ButtonSegment(value: false, label: Text('% Off')),
              ],
              selected: {_isFlat},
              onSelectionChanged: (s) => setState(() => _isFlat = s.first),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _isFlat ? 'Amount (₹)' : 'Percent (%)',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _minCartCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Min cart (₹)', border: OutlineInputBorder(), isDense: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _maxDiscCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Max discount (₹)', border: OutlineInputBorder(), isDense: true),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _paymentCtrl,
            decoration: const InputDecoration(
              labelText: 'Card / payment req (optional)',
              hintText: 'e.g. HDFC credit card',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 16),
            const SizedBox(width: 8),
            Text('Expires: ${_expiresAt.day}/${_expiresAt.month}/${_expiresAt.year}',
                style: theme.textTheme.bodyMedium),
            const SizedBox(width: 8),
            TextButton(onPressed: _pickExpiry, child: const Text('Change')),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save coupon'),
            ),
          ),
        ],
      ),
    );
  }
}
