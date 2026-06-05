import 'package:sqflite/sqflite.dart';

import '../models/order.dart';
import 'db_helper.dart';

class OrdersDao {
  final DbHelper _db;
  OrdersDao(this._db);

  Future<void> insert(Order order) async {
    final db = await _db.db;
    await db.insert('orders', order.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Order>> getRecent({int limit = 20}) async {
    final db = await _db.db;
    final rows = await db.query('orders', orderBy: 'ordered_at DESC', limit: limit);
    return rows.map(Order.fromMap).toList();
  }

  Future<void> updateRating(String orderId, int rating) async {
    final db = await _db.db;
    await db.update('orders', {'my_rating': rating}, where: 'order_id = ?', whereArgs: [orderId]);
  }

  Future<List<String>> getBadRatedRestaurants({int ratingThreshold = 2}) async {
    final db = await _db.db;
    final rows = await db.query(
      'orders',
      columns: ['restaurant'],
      where: 'my_rating <= ?',
      whereArgs: [ratingThreshold],
      distinct: true,
    );
    return rows.map((r) => r['restaurant'] as String).toList();
  }
}
