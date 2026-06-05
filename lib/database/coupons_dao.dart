import 'package:sqflite/sqflite.dart';

import '../models/coupon.dart';
import 'db_helper.dart';

class CouponsDao {
  final DbHelper _db;
  CouponsDao(this._db);

  Future<void> insert(Coupon coupon) async {
    final db = await _db.db;
    await db.insert('coupons', coupon.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Coupon>> getActive() async {
    final db = await _db.db;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query('coupons', where: 'expires_at > ?', whereArgs: [now]);
    return rows.map(Coupon.fromMap).toList();
  }

  Future<List<Coupon>> getActiveForApp(String app) async {
    final db = await _db.db;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      'coupons',
      where: 'app = ? AND expires_at > ?',
      whereArgs: [app, now],
    );
    return rows.map(Coupon.fromMap).toList();
  }

  Future<void> delete(int id) async {
    final db = await _db.db;
    await db.delete('coupons', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteExpired() async {
    final db = await _db.db;
    final now = DateTime.now().toIso8601String();
    await db.delete('coupons', where: 'expires_at <= ?', whereArgs: [now]);
  }
}
