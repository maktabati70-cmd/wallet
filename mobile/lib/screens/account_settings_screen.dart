import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import '../core/api_client.dart';
import '../core/secure_store.dart';
import '../core/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'unlock_screen.dart';
import 'welcome_screen.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  RemoteConfig? _config;

  @override
  void initState() {
    super.initState();
    ApiClient.instance.config().then((c) {
      if (mounted) setState(() => _config = c);
    }).catchError((Object _) {});
  }

  Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  Future<void> _removeWallet() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Remove wallet from this device?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
              'This deletes the wallet and all app data from this phone. Your funds stay on the '
              'blockchain, but you can only access them again with your recovery phrase.\n\n'
              'Type REMOVE to confirm.',
            ),
            const SizedBox(height: 12),
            TextField(controller: controller, onChanged: (_) => setLocal(() {})),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: controller.text.trim() == 'REMOVE' ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (confirmed != true || !mounted) return;
    if (!await requirePin(context, title: 'Enter PIN to remove wallet')) return;
    await SecureStore.instance.wipe();
    WalletSession.instance.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final address = WalletSession.instance.address ?? '';
    final c = _config;
    return Scaffold(
      appBar: AppBar(title: const Text('Account & about')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Wallet address', style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 6),
              AddressText(address, fontSize: 13),
              const SizedBox(height: 8),
              InfoRow('Network', c == null ? '…' : (c.isTestnet ? 'TRON ${c.network} (testnet)' : 'TRON')),
              const InfoRow('Wallet type', 'Self-custody (you hold the keys)'),
              const InfoRow('App version', AppConfig.appVersion),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        if (c != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Fees', style: TextStyle(fontWeight: FontWeight.w700)),
                InfoRow('Service fee', '${c.serviceFeePercent}%'),
                InfoRow('Minimum / maximum service fee', '${c.minServiceFee} / ${c.maxServiceFee} USDT'),
                const InfoRow('Network resource fee', 'Shown per transfer'),
                const SizedBox(height: 6),
                Text(c.resourceDisclosure,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
              ]),
            ),
          ),
        const SizedBox(height: 16),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.support_agent_outlined),
              title: const Text('Contact support'),
              subtitle: const Text(AppConfig.supportEmail),
              onTap: () => _open('mailto:${AppConfig.supportEmail}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy policy'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _open(AppConfig.privacyPolicyUrl),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Terms of use'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _open(AppConfig.termsUrl),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.danger),
            title: const Text('Remove wallet from this device',
                style: TextStyle(color: AppColors.danger)),
            subtitle: const Text('Deletes all app data on this phone. We hold no account to delete.'),
            onTap: _removeWallet,
          ),
        ),
      ]),
    );
  }
}
