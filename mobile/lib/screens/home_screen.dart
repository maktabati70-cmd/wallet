import 'package:flutter/material.dart';

import '../app_config.dart';
import '../core/api_client.dart';
import '../core/money.dart';
import '../core/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'account_settings_screen.dart';
import 'history_screen.dart';
import 'receive_screen.dart';
import 'security_settings_screen.dart';
import 'send_screen.dart';
import 'tx_details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiClient.instance;
  String get _address => WalletSession.instance.address ?? '';

  RemoteConfig? _config;
  Balance? _balance;
  List<TxItem> _recent = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await _api.config();
      final balance = await _api.balance(_address);
      final history = await _api.history(_address, limit: 5);
      if (!mounted) return;
      setState(() {
        _config = config;
        _balance = balance;
        _recent = history.items;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings_outlined),
            onSelected: (v) => _open(v == 'security'
                ? const SecuritySettingsScreen()
                : const AccountSettingsScreen()),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'security', child: Text('Security')),
              PopupMenuItem(value: 'account', child: Text('Account & about')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          TestnetBanner(network: _config?.network ?? 'nile'),
          const SizedBox(height: 12),
          _BalanceCard(
            address: _address,
            balance: _balance,
            loading: _loading && _balance == null,
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.south_west_rounded,
                label: 'Receive',
                onTap: () => _open(ReceiveScreen(network: _config?.network ?? 'nile')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                icon: Icons.north_east_rounded,
                label: 'Send',
                onTap: () => _open(SendScreen(availableMicro: _balance?.usdtMicro ?? 0)),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          SectionTitle('Recent transactions',
              action: TextButton(
                onPressed: () => _open(const HistoryScreen()),
                child: const Text('See all'),
              )),
          if (_error != null)
            ErrorRetry(message: _error!, onRetry: _load)
          else if (_loading && _recent.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_recent.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.receipt_long_outlined),
                title: Text('No transactions yet'),
                subtitle: Text('Your USDT transfers will appear here.'),
              ),
            )
          else
            Card(
              child: Column(children: [
                for (final tx in _recent)
                  TxTile(tx, onTap: () => _open(TxDetailsScreen(tx: tx))),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.address, required this.balance, required this.loading});
  final String address;
  final Balance? balance;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.brandDark, AppColors.brand],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Available balance', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 8),
        loading
            ? const SizedBox(
                height: 40,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                ),
              )
            : Text(
                '${balance == null ? '—' : Usdt.format(balance!.usdtMicro)} USDT',
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
              ),
        const SizedBox(height: 14),
        InkWell(
          onTap: () => copyToClipboard(context, address, 'Address'),
          child: Row(children: [
            Expanded(
              child: Text(shortAddress(address),
                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace')),
            ),
            const Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
          ]),
        ),
      ]),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(children: [
            Icon(icon, color: AppColors.brand, size: 28),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
