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
    return openDatabase(path, version: 1, onCreate: _onCreate);
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

    await db.execute('''
      CREATE TABLE preferences (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        diet_type TEXT NOT NULL DEFAULT 'none',
        fav_cuisines TEXT NOT NULL DEFAULT '[]',
        avoid_items TEXT NOT NULL DEFAULT '[]',
        max_spend_lunch INTEGER NOT NULL DEFAULT 300,
        max_spend_dinner INTEGER NOT NULL DEFAULT 500,
        ok_addons TEXT NOT NULL DEFAULT '[]',
        payment_methods TEXT NOT NULL DEFAULT '[]',
        home_address TEXT,
        work_address TEXT
      )
    ''');

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
}
