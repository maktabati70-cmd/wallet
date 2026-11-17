import 'package:flutter/material.dart';

import '../app_config.dart';
import '../core/secure_store.dart';
import '../core/session.dart';
import '../theme.dart';
import 'unlock_screen.dart';
import 'welcome_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final store = SecureStore.instance;
    final minDisplay = Future<void>.delayed(const Duration(milliseconds: 700));
    final hasWallet = await store.hasWallet();
    await minDisplay;
    if (hasWallet) WalletSession.instance.address = await store.readAddress();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => hasWallet ? const UnlockScreen() : const WelcomeScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brandDark,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 20),
          const Text(AppConfig.appName,
              style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('USDT · TRC20', style: TextStyle(color: Colors.white70)),
        ]),
      ),
    );
  }
}
