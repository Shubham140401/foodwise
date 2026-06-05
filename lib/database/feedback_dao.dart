import 'package:sqflite/sqflite.dart';

import '../models/feedback.dart';
import 'db_helper.dart';

class FeedbackDao {
  final DbHelper _db;
  FeedbackDao(this._db);

  Future<void> insert(FeedbackEntry entry) async {
    final db = await _db.db;
    await db.insert('feedback', entry.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<FeedbackEntry>> getAll() async {
    final db = await _db.db;
    final rows = await db.query('feedback', orderBy: 'rated_at DESC');
    return rows.map(FeedbackEntry.fromMap).toList();
  }
}
