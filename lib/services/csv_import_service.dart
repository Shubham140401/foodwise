import 'dart:convert';

import 'package:csv/csv.dart';

import '../models/order.dart';

// Statuses to import. Anything else (cancelled, Payment Incomplete, etc.) is skipped.
const _importableStatuses = {'Delivered', 'Refund Completed'};

class CsvImportResult {
  final int imported;
  final int skipped;
  final List<String> errors;

  const CsvImportResult({
    required this.imported,
    required this.skipped,
    required this.errors,
  });
}

class CsvImportService {
  /// Parse a Swiggy order history CSV file.
  ///
  /// Expected columns (from the real export):
  /// order_id, order_time, order_status, restaurant_name, restaurant_locality,
  /// restaurant_city, items, item_total, packing_charges, delivery_charges,
  /// order_discount, coupon_applied, order_tax, order_total, payment_method,
  /// delivery_person, delivery_time_mins, sla_time_mins, on_time
  List<Order> parseSwiggy(String csvContent) {
    final rows = _parseCsv(csvContent);
    if (rows.isEmpty) return [];

    final header = rows.first.map((e) => e.toString().trim()).toList();
    final idx = _indexMap(header);

    final orders = <Order>[];
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 8) continue;

      try {
        final status = _cell(row, idx, 'order_status');
        if (!_importableStatuses.contains(status)) continue;

        final orderedAt = DateTime.parse(_cell(row, idx, 'order_time'));
        final itemsRaw = _cell(row, idx, 'items');

        orders.add(Order(
          orderId: _cell(row, idx, 'order_id'),
          app: 'Swiggy',
          restaurant: _cell(row, idx, 'restaurant_name'),
          itemsJson: jsonEncode(_parseSwiggyItems(itemsRaw)),
          subtotal: _intCell(row, idx, 'item_total'),
          deliveryFee: _intCell(row, idx, 'delivery_charges'),
          platformFee: _intCell(row, idx, 'packing_charges'),
          couponUsed: _nullableCell(row, idx, 'coupon_applied'),
          discount: _intCell(row, idx, 'order_discount'),
          totalPaid: _intCell(row, idx, 'order_total'),
          myRating: null,
          orderedAt: orderedAt,
          mealType: _mealType(orderedAt),
        ));
      } catch (_) {
        // Skip malformed rows silently
      }
    }
    return orders;
  }

  /// Parse a Zomato order history CSV file.
  ///
  /// Expected columns (from the real export):
  /// order_id, order_date, order_status, restaurant_name, locality,
  /// city, items, order_total, delivery_address, rating
  List<Order> parseZomato(String csvContent) {
    final rows = _parseCsv(csvContent);
    if (rows.isEmpty) return [];

    final header = rows.first.map((e) => e.toString().trim()).toList();
    final idx = _indexMap(header);

    final orders = <Order>[];
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 7) continue;

      try {
        final status = _cell(row, idx, 'order_status');
        if (!_importableStatuses.contains(status)) continue;

        final dateStr = _cell(row, idx, 'order_date');
        final orderedAt = _parseZomatoDate(dateStr);
        if (orderedAt == null) continue;

        final itemsRaw = _cell(row, idx, 'items');
        final totalStr = _cell(row, idx, 'order_total').replaceAll(',', '');
        final total = (double.tryParse(totalStr) ?? 0).round();

        final ratingStr = _nullableCell(row, idx, 'rating');
        final rating = ratingStr != null ? int.tryParse(ratingStr) : null;

        orders.add(Order(
          orderId: _cell(row, idx, 'order_id'),
          app: 'Zomato',
          restaurant: _cell(row, idx, 'restaurant_name'),
          itemsJson: jsonEncode(_parseZomatoItems(itemsRaw)),
          // Zomato export only gives the final total — no subtotal breakdown.
          subtotal: total,
          deliveryFee: 0,
          platformFee: 0,
          couponUsed: null,
          discount: 0,
          totalPaid: total,
          myRating: rating,
          orderedAt: orderedAt,
          mealType: _mealType(orderedAt),
        ));
      } catch (_) {
        // Skip malformed rows silently
      }
    }
    return orders;
  }

  // ── CSV parsing ──────────────────────────────────────────────────────────

  List<List<dynamic>> _parseCsv(String content) {
    return const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(content.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
  }

  Map<String, int> _indexMap(List<String> header) =>
      {for (int i = 0; i < header.length; i++) header[i]: i};

  String _cell(List<dynamic> row, Map<String, int> idx, String col) {
    final i = idx[col];
    if (i == null || i >= row.length) return '';
    return row[i].toString().trim();
  }

  String? _nullableCell(List<dynamic> row, Map<String, int> idx, String col) {
    final v = _cell(row, idx, col);
    return v.isEmpty ? null : v;
  }

  int _intCell(List<dynamic> row, Map<String, int> idx, String col) {
    final raw = _cell(row, idx, col).replaceAll(',', '');
    return (double.tryParse(raw) ?? 0).round();
  }

  // ── Item name extraction ────────────────────────────────────────────────

  // Swiggy format: "Spicy Grilled Chicken Pizza (Medium) x1 @479 | Fries x2 @99"
  List<String> _parseSwiggyItems(String raw) {
    if (raw.isEmpty) return [];
    return raw
        .split(' | ')
        .map((part) {
          // Strip " xN @price" suffix
          final match = RegExp(r'^(.+?)\s+x\d+').firstMatch(part.trim());
          return match != null ? match.group(1)!.trim() : part.trim();
        })
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // Zomato format: "1 x Kolkata Chicken Biryani, 1 x Mutter Paneer"
  // Items are separated by ", " but item names can also contain commas, so
  // we split on the "N x " pattern instead.
  List<String> _parseZomatoItems(String raw) {
    if (raw.isEmpty) return [];
    // Split on boundaries like ", 1 x " or ", 2 x " etc.
    final parts = raw.split(RegExp(r',\s*\d+\s+x\s+'));
    final results = <String>[];
    for (int i = 0; i < parts.length; i++) {
      var part = parts[i].trim();
      // First part still has the leading "N x "
      part = part.replaceFirst(RegExp(r'^\d+\s+x\s+'), '').trim();
      if (part.isNotEmpty) results.add(part);
    }
    return results;
  }

  // ── Date parsing ─────────────────────────────────────────────────────────

  // Zomato format: "May 24, 2026 at 01:24 PM"
  DateTime? _parseZomatoDate(String raw) {
    if (raw.isEmpty) return null;
    try {
      // Normalise to "May 24 2026 01:24 PM"
      final normalised = raw
          .replaceAll(',', '')
          .replaceAll(' at ', ' ')
          .trim();
      // Dart can't parse 12h format directly — do it manually.
      final parts = normalised.split(' ');
      // parts: ["May", "24", "2026", "01:24", "PM"]
      if (parts.length < 5) return null;
      const months = {
        'January': 1, 'February': 2, 'March': 3, 'April': 4,
        'May': 5, 'June': 6, 'July': 7, 'August': 8,
        'September': 9, 'October': 10, 'November': 11, 'December': 12,
      };
      final month = months[parts[0]];
      if (month == null) return null;
      final day = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      final timeParts = parts[3].split(':');
      int hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final ampm = parts[4].toUpperCase();
      if (ampm == 'PM' && hour != 12) hour += 12;
      if (ampm == 'AM' && hour == 12) hour = 0;
      return DateTime(year, month, day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _mealType(DateTime dt) {
    final h = dt.hour;
    if (h >= 11 && h < 16) return 'lunch';
    if (h >= 19 && h < 23) return 'dinner';
    return 'late_night';
  }
}
