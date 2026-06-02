# foodwise — Food Deal Agent

## What this app does
Personal Android app that finds the best food deal across Swiggy, Zomato, and Blinkit
at the moment the user opens it. Compares true final prices (item + delivery + platform
fee - coupon), suggests smart cart add-ons to unlock coupon thresholds, and uses phone
screen time data to detect ordering intent and mood.

## Critical behaviour rule
The app runs ONLY when the user opens it. No background services, no WorkManager
periodic jobs, no AlarmManager intervals, no foreground services. Everything is
triggered on app open and stops when the user closes it. Apply this constraint to
every feature built.

## Architecture — 3 layers
1. **Claude API** (`claude-sonnet-4-20250514`) — reasoning brain. Receives a structured
   prompt built from user data and returns a natural language recommendation. Handles
   judgment, craving inference, and decision fatigue detection. Never does arithmetic.
2. **Rule engine** (pure Dart) — all math: coupon threshold checks, net saving
   calculations after add-ons, price ranking across apps, expiry validation, payment
   method filtering.
3. **Local SQLite** (sqflite) — all data lives on device. Never sent to any server
   except the prompt text to Claude API.

## Full app-open flow
1. Read today's usage stats live from Android UsageStatsManager API
2. Query SQLite: last 20 orders, active coupons, preferences, bad-rated restaurants
3. Rule engine calculates net savings per coupon + add-on combos
4. Assemble prompt with all context
5. POST to Claude API → get recommendation
6. Display recommendation on screen
7. Log outcome to feedback table when user orders or dismisses

## Database — 5 SQLite tables (sqflite)

### orders
```
order_id TEXT, app TEXT, restaurant TEXT, items_json TEXT,
subtotal INTEGER, delivery_fee INTEGER, platform_fee INTEGER,
coupon_used TEXT, discount INTEGER, total_paid INTEGER,
my_rating INTEGER, ordered_at DATETIME, meal_type TEXT
```

### usage_sessions
```
date DATE, app TEXT, total_mins INTEGER, open_count INTEGER,
order_placed BOOLEAN, signal TEXT
-- signal values: low_intent | medium_intent | high_intent | decision_fatigue
```

### coupons
```
app TEXT, code TEXT, discount_pct INTEGER, flat_discount INTEGER,
min_cart INTEGER, max_discount INTEGER, expires_at DATETIME,
payment_req TEXT, one_time BOOLEAN
```

### preferences
```
diet_type TEXT, fav_cuisines TEXT (JSON array),
avoid_items TEXT (JSON array), max_spend_lunch INTEGER,
max_spend_dinner INTEGER, ok_addons TEXT (JSON array),
payment_methods TEXT (JSON array), home_address TEXT,
work_address TEXT
```

### feedback
```
order_id TEXT, followed_agent BOOLEAN,
satisfaction TEXT (good | ok | bad), agent_was_right BOOLEAN,
rated_at DATETIME
```

## One-time setup (first launch)
- Import order history CSV exported from Swiggy and Zomato accounts
- Fill preference onboarding form (diet, cuisines, budget, add-ons, payment methods)
- Grant PACKAGE_USAGE_STATS permission (Settings → Special access)
- Grant ACCESS_FINE_LOCATION permission
- Save home and work delivery addresses
After setup, the app learns from new orders automatically.

## Live data on every app open (not stored historically)
- UsageStatsManager → today's minutes per app
- GPS location → current position for delivery fee accuracy
- System clock → meal type inference (lunch / dinner / late night)
- Coupons → manually entered or read via Accessibility API

## Intent scoring (rule engine, runs before Claude call)
| Usage time | Signal | Agent behaviour |
|---|---|---|
| 0–3 min | low_intent | passive |
| 4–8 min | medium_intent | show top 3 deals proactively |
| 9–15 min | high_intent | surface best deal with confidence |
| 16+ min | decision_fatigue | simplify to one clear option only |

## Claude API prompt structure
```
System: You are a personal food ordering agent. Be concise.
        One recommendation. Show true final price always.
        Never suggest items the user dislikes.

Context blocks:
  [USER PREFERENCES]      — diet, budget, cuisines, avoid list
  [TODAY BEHAVIOUR]       — usage mins per app, intent signal, time of day
  [AVAILABLE DEALS]       — rule engine output: best coupon per app,
                            net saving after add-ons, final prices
  [ORDER HISTORY SIGNAL]  — top cuisines, last visited restaurants,
                            bad-rated places to exclude
  [TASK]                  — return one recommendation, max 3 sentences,
                            show savings vs second-best option
```

## Tech stack
- Framework: Flutter (Dart), Android only
- IDE: VS Code with Flutter + Dart extensions
- State management: provider
- Database: sqflite + path_provider
- API calls: http
- Location: geolocator
- Usage stats: app_usage
- Notifications: flutter_local_notifications
- Secure key storage: flutter_secure_storage
- Env config: flutter_dotenv

## pubspec.yaml dependencies
```yaml
sqflite: ^2.3.0
path_provider: ^2.1.0
http: ^1.1.0
geolocator: ^10.1.0
flutter_secure_storage: ^9.0.0
app_usage: ^2.0.2
flutter_local_notifications: ^16.1.0
provider: ^6.1.1
shared_preferences: ^2.2.2
flutter_dotenv: ^5.1.0
```

## Android permissions (AndroidManifest.xml)
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.PACKAGE_USAGE_STATS"
  tools:ignore="ProtectedPermissions"/>
```

## Project file structure
```
lib/
  main.dart
  database/
    db_helper.dart          — SQLite init, all 5 table creation
    orders_dao.dart         — CRUD for orders table
    coupons_dao.dart        — CRUD for coupons table
    preferences_dao.dart    — read/write preferences
    feedback_dao.dart       — log post-order feedback
    usage_dao.dart          — store usage session signals
  services/
    usage_stats_service.dart — reads Android UsageStatsManager
    location_service.dart    — gets GPS, manages saved addresses
    claude_service.dart      — builds prompt, calls Claude API, parses response
    rule_engine.dart         — all coupon math and price comparison
  screens/
    onboarding_screen.dart   — first launch: CSV import + preferences
    home_screen.dart         — main recommendation screen
    history_screen.dart      — past orders and savings summary
    settings_screen.dart     — preferences, addresses, API key
  widgets/
    deal_card.dart           — displays a single app's deal
    addon_suggestion.dart    — shows smart add-on prompt
    intent_indicator.dart    — subtle usage signal display
  models/
    order.dart
    coupon.dart
    preference.dart
    usage_session.dart
    feedback.dart
```

## Git
- Repo: foodwise (private)
- Branch strategy: feature branches → PR → merge to main
- Never commit: `.env` (contains CLAUDE_API_KEY)

## Build order
Start with `db_helper.dart` (all 5 tables) → `preferences_dao.dart` →
`onboarding_screen.dart` → then agent logic. Real preference data must
exist before building the Claude/rule-engine layer.
