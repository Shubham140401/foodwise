import 'package:sqflite/sqflite.dart';

import '../models/preference.dart';
import 'db_helper.dart';

class PreferencesDao {
  final DbHelper _db;
  PreferencesDao(this._db);

  Future<Preference?> get() async {
    final db = await _db.db;
    final rows = await db.query('preferences', where: 'id = 1');
    if (rows.isEmpty) return null;
    return Preference.fromMap(rows.first);
  }

  Future<void> save(Preference pref) async {
    final db = await _db.db;
    await db.insert(
      'preferences',
      pref.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
