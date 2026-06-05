import 'package:sqflite/sqflite.dart';

import '../models/usage_session.dart';
import 'db_helper.dart';

class UsageDao {
  final DbHelper _db;
  UsageDao(this._db);

  Future<void> insertOrReplace(UsageSession session) async {
    final db = await _db.db;
    await db.insert('usage_sessions', session.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<UsageSession>> getForDate(DateTime date) async {
    final db = await _db.db;
    final dateStr = date.toIso8601String().split('T').first;
    final rows = await db.query('usage_sessions', where: 'date = ?', whereArgs: [dateStr]);
    return rows.map(UsageSession.fromMap).toList();
  }

  Future<void> markOrderPlaced(String app, DateTime date) async {
    final db = await _db.db;
    final dateStr = date.toIso8601String().split('T').first;
    await db.update(
      'usage_sessions',
      {'order_placed': 1},
      where: 'date = ? AND app = ?',
      whereArgs: [dateStr, app],
    );
  }

  Future<List<UsageSession>> getRecent({int days = 7}) async {
    final db = await _db.db;
    final cutoff = DateTime.now().subtract(Duration(days: days)).toIso8601String().split('T').first;
    final rows = await db.query(
      'usage_sessions',
      where: 'date >= ?',
      whereArgs: [cutoff],
      orderBy: 'date DESC',
    );
    return rows.map(UsageSession.fromMap).toList();
  }
}
