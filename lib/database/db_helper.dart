import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DbHelper {
  static final DbHelper _instance = DbHelper._internal();
  factory DbHelper() => _instance;
  DbHelper._internal();

  static Database? _db;

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'foodwise.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE orders (
        order_id TEXT PRIMARY KEY,
        app TEXT NOT NULL,
        restaurant TEXT NOT NULL,
        items_json TEXT NOT NULL,
        subtotal INTEGER NOT NULL,
        delivery_fee INTEGER NOT NULL,
        platform_fee INTEGER NOT NULL,
        coupon_used TEXT,
        discount INTEGER NOT NULL DEFAULT 0,
        total_paid INTEGER NOT NULL,
        my_rating INTEGER,
        ordered_at DATETIME NOT NULL,
        meal_type TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE usage_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date DATE NOT NULL,
        app TEXT NOT NULL,
        total_mins INTEGER NOT NULL DEFAULT 0,
        open_count INTEGER NOT NULL DEFAULT 0,
        order_placed INTEGER NOT NULL DEFAULT 0,
        signal TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE coupons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        app TEXT NOT NULL,
        code TEXT NOT NULL,
        discount_pct INTEGER NOT NULL DEFAULT 0,
        flat_discount INTEGER NOT NULL DEFAULT 0,
        min_cart INTEGER NOT NULL DEFAULT 0,
        max_discount INTEGER NOT NULL DEFAULT 0,
        expires_at DATETIME NOT NULL,
        payment_req TEXT,
        one_time INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await _createPreferencesTable(db);

    await db.execute('''
      CREATE TABLE feedback (
        order_id TEXT PRIMARY KEY,
        followed_agent INTEGER NOT NULL DEFAULT 0,
        satisfaction TEXT NOT NULL,
        agent_was_right INTEGER NOT NULL DEFAULT 0,
        rated_at DATETIME NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS preferences');
      await _createPreferencesTable(db);
    }
    if (oldVersion < 3) {
      final cols = await db.rawQuery('PRAGMA table_info(preferences)');
      final hasCol = cols.any((c) => c['name'] == 'bank_cards');
      if (!hasCol) {
        await db.execute(
            "ALTER TABLE preferences ADD COLUMN bank_cards TEXT NOT NULL DEFAULT '[]'");
      }
    }
  }

  Future<void> _createPreferencesTable(Database db) async {
    await db.execute('''
      CREATE TABLE preferences (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        diet_type TEXT NOT NULL DEFAULT 'none',
        num_people INTEGER NOT NULL DEFAULT 1,
        people_prefs TEXT NOT NULL DEFAULT '[]',
        bank_cards TEXT NOT NULL DEFAULT '[]'
      )
    ''');
  }
}
