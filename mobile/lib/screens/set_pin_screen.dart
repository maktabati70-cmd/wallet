import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/biometrics.dart';
import '../core/secure_store.dart';
import '../core/session.dart';
import '../core/wallet_crypto.dart';
import '../theme.dart';
import '../widgets/pin_pad.dart';
import 'home_screen.dart';

/// Sets the app PIN. With [mnemonic] it finishes wallet creation/import;
/// without it, it changes the PIN of an existing wallet.
class SetPinScreen extends StatefulWidget {
  const SetPinScreen({super.key, this.mnemonic});
  final String? mnemonic;

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  final _padKey = GlobalKey<PinPadState>();
  String? _first;
  String? _error;
  bool _saving = false;

  static bool _weak(String pin) {
    if (RegExp(r'^(\d)\1+$').hasMatch(pin)) return true; // 111111
    const seq = '01234567890';
    const rev = '09876543210';
    return seq.contains(pin) || rev.contains(pin);
  }

  Future<void> _onPin(String pin) async {
    if (_first == null) {
      if (_weak(pin)) {
        setState(() => _error = 'This PIN is too easy to guess. Choose another.');
        return;
      }
      setState(() {
        _first = pin;
        _error = null;
      });
      return;
    }
    if (pin != _first) {
      setState(() {
        _first = null;
        _error = 'PINs did not match. Try again.';
      });
      return;
    }
    await _save(pin);
  }

  Future<void> _save(String pin) async {
    setState(() => _saving = true);
    final store = SecureStore.instance;
    try {
      final mnemonic = widget.mnemonic;
      if (mnemonic != null) {
        final address = await compute(deriveAddressInIsolate, mnemonic);
        await store.saveWallet(mnemonic: mnemonic, address: address);
        await store.setPin(pin);
        WalletSession.instance
          ..address = address
          ..unlocked = true;
        if (!mounted) return;
        await _offerBiometrics();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
          (_) => false,
        );
      } else {
        await store.setPin(pin);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN changed')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save the wallet securely: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _offerBiometrics() async {
    if (!await Biometrics.available() || !mounted) return;
    final enable = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Use fingerprint unlock?'),
        content: const Text('You can unlock the app with your fingerprint instead of the PIN. '
            'You can change this later in Security settings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enable')),
        ],
      ),
    );
    if (enable == true && await Biometrics.authenticate('Confirm to enable fingerprint unlock')) {
      await SecureStore.instance.setBiometricEnabled(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirming = _first != null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.mnemonic != null ? 'Create a PIN' : 'New PIN')),
      body: SafeArea(
        child: Center(
          child: _saving
              ? const Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Securing your wallet…'),
                ])
              : SingleChildScrollView(
                  child: Column(children: [
                    Text(confirming ? 'Confirm your 6-digit PIN' : 'Choose a 6-digit PIN',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    const Text('The PIN unlocks the app on this device.',
                        style: TextStyle(color: AppColors.muted)),
                    SizedBox(
                      height: 40,
                      child: Center(
                        child: Text(_error ?? '', style: const TextStyle(color: AppColors.danger)),
                      ),
                    ),
                    PinPad(key: _padKey, onCompleted: _onPin),
                  ]),
                ),
        ),
      ),
    );
  }
}
