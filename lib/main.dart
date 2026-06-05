import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database/db_helper.dart';
import 'database/preferences_dao.dart';
import 'database/orders_dao.dart';
import 'database/coupons_dao.dart';
import 'database/feedback_dao.dart';
import 'database/usage_dao.dart';
import 'services/rule_engine.dart';
import 'services/claude_service.dart';
import 'services/location_service.dart';
import 'services/usage_stats_service.dart';
import 'services/background_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await BackgroundService.initialize();
  await BackgroundService.registerPeriodicTask();
  runApp(const FoodwiseApp());
}

class FoodwiseApp extends StatelessWidget {
  const FoodwiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final db = DbHelper();
    return MultiProvider(
      providers: [
        Provider(create: (_) => db),
        Provider(create: (_) => PreferencesDao(db)),
        Provider(create: (_) => OrdersDao(db)),
        Provider(create: (_) => CouponsDao(db)),
        Provider(create: (_) => FeedbackDao(db)),
        Provider(create: (_) => UsageDao(db)),
        Provider(create: (_) => LocationService()),
        Provider(create: (_) => UsageStatsService()),
        Provider(create: (_) => RuleEngine()),
        Provider(create: (ctx) => ClaudeService(ctx.read<RuleEngine>())),
      ],
      child: MaterialApp(
        title: 'foodwise',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF6B35)),
          useMaterial3: true,
        ),
        home: const _AppGate(),
      ),
    );
  }
}

class _AppGate extends StatefulWidget {
  const _AppGate();

  @override
  State<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<_AppGate> {
  bool? _onboardingDone;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _onboardingDone = prefs.getBool('onboarding_done') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_onboardingDone == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_onboardingDone!) {
      return OnboardingScreen(onComplete: () => setState(() => _onboardingDone = true));
    }
    return const HomeScreen();
  }
}
