import 'package:flutter/material.dart';

import '../core/biometrics.dart';
import '../core/secure_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'create_wallet_screen.dart';
import 'set_pin_screen.dart';
import 'unlock_screen.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final _store = SecureStore.instance;
  bool _bioAvailable = false;
  bool _bioEnabled = false;
  int _autoLock = 60;

  static const _autoLockOptions = {0: 'Immediately', 60: 'After 1 minute', 300: 'After 5 minutes'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final available = await Biometrics.available();
    final enabled = await _store.biometricEnabled();
    final lock = await _store.autoLockSeconds();
    if (!mounted) return;
    setState(() {
      _bioAvailable = available;
      _bioEnabled = enabled;
      _autoLock = _autoLockOptions.containsKey(lock) ? lock : 60;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      if (!await requirePin(context, title: 'Confirm with PIN')) return;
      if (!await Biometrics.authenticate('Confirm to enable fingerprint unlock')) return;
    }
    await _store.setBiometricEnabled(value);
    if (mounted) setState(() => _bioEnabled = value);
  }

  Future<void> _changePin() async {
    if (!await requirePin(context, title: 'Enter current PIN')) return;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SetPinScreen()));
  }

  Future<void> _showPhrase() async {
    if (!await requirePin(context, title: 'Enter PIN to view phrase')) return;
    final phrase = await _store.readMnemonic();
    if (phrase == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Recovery phrase')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const WarningCard(
            text: 'Never share these words. Anyone who has them can take your funds. '
                'Support will never ask for them.',
          ),
          const SizedBox(height: 16),
          PhraseGrid(words: phrase.split(' ')),
        ]),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: const Text('Change PIN'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _changePin,
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: const Text('Fingerprint unlock'),
              subtitle: Text(_bioAvailable ? 'Unlock without typing your PIN' : 'Not available on this device'),
              value: _bioEnabled,
              onChanged: _bioAvailable ? _toggleBiometric : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Auto-lock'),
              trailing: DropdownButton<int>(
                value: _autoLock,
                underline: const SizedBox.shrink(),
                items: [
                  for (final e in _autoLockOptions.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  await _store.setAutoLockSeconds(v);
                  if (mounted) setState(() => _autoLock = v);
                },
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.key_outlined, color: AppColors.warning),
            title: const Text('Show recovery phrase'),
            subtitle: const Text('Requires your PIN'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showPhrase,
          ),
        ),
        const SizedBox(height: 16),
        const WarningCard(
          icon: Icons.shield_outlined,
          text: 'Security tips: keep your phone updated, never install apps from unknown '
              'sources, and always check the full recipient address before sending.',
        ),
      ]),
    );
  }
}
