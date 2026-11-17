import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_config.dart';
import 'core/secure_store.dart';
import 'core/session.dart';
import 'screens/splash_screen.dart';
import 'screens/unlock_screen.dart';
import 'theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const WalletApp());
}

class WalletApp extends StatefulWidget {
  const WalletApp({super.key});

  @override
  State<WalletApp> createState() => _WalletAppState();
}

class _WalletAppState extends State<WalletApp> with WidgetsBindingObserver {
  bool _lockScreenShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    final session = WalletSession.instance;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (session.unlocked) session.backgroundedAt ??= DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final since = session.backgroundedAt;
    session.backgroundedAt = null;
    if (!session.unlocked || since == null || _lockScreenShown) return;

    final limit = await SecureStore.instance.autoLockSeconds();
    if (DateTime.now().difference(since).inSeconds < limit) return;

    session.lock();
    _lockScreenShown = true;
    await navigatorKey.currentState?.push(MaterialPageRoute<void>(
      builder: (_) => const UnlockScreen(overlay: true),
      fullscreenDialog: true,
    ));
    _lockScreenShown = false;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // English only, left-to-right.
      locale: const Locale('en'),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.ltr, child: child!),
      home: const SplashScreen(),
    );
  }
}
