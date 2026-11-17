import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'create_wallet_screen.dart';
import 'import_wallet_screen.dart';

/// Replaces "Registration / Login" for a non-custodial wallet: there is no
/// server account. The user creates or imports a wallet that only they control.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const TestnetBanner(),
            const Spacer(),
            const Icon(Icons.account_balance_wallet_rounded, size: 64, color: AppColors.brand),
            const SizedBox(height: 20),
            const Text(AppConfig.appName,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            const Text(
              'A simple, self-custody wallet for USDT on the TRON network.\n'
              'Your keys stay on this device. Only you control your funds.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const CreateWalletScreen())),
              child: const Text('Create a new wallet'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ImportWalletScreen())),
              child: const Text('I already have a wallet'),
            ),
            const SizedBox(height: 16),
            const Wrap(alignment: WrapAlignment.center, children: [
              Text('By continuing you agree to the ',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
              _Link('Terms', AppConfig.termsUrl),
              Text(' and ', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              _Link('Privacy Policy', AppConfig.privacyPolicyUrl),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.text, this.url);
  final String text;
  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Text(text,
          style: const TextStyle(
              fontSize: 12, color: AppColors.brand, decoration: TextDecoration.underline)),
    );
  }
}
