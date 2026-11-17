import 'dart:async';

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../core/biometrics.dart';
import '../core/secure_store.dart';
import '../core/session.dart';
import '../theme.dart';
import '../widgets/pin_pad.dart';
import 'home_screen.dart';
import 'import_wallet_screen.dart';

enum UnlockMode { startup, overlay, confirm }

/// Asks for the PIN again before a sensitive action. Returns true on success.
Future<bool> requirePin(BuildContext context, {String title = 'Enter your PIN'}) async {
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
    builder: (_) => UnlockScreen(mode: UnlockMode.confirm, title: title),
    fullscreenDialog: true,
  ));
  return ok ?? false;
}

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, bool overlay = false, UnlockMode? mode, this.title})
      : mode = mode ?? (overlay ? UnlockMode.overlay : UnlockMode.startup);

  final UnlockMode mode;
  final String? title;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _store = SecureStore.instance;
  String? _message;
  bool _biometric = false;
  Duration _locked = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final enabled = widget.mode != UnlockMode.confirm &&
        await _store.biometricEnabled() &&
        await Biometrics.available();
    final locked = await _store.lockRemaining();
    if (!mounted) return;
    setState(() => _biometric = enabled);
    if (locked > Duration.zero) _startLockTimer(locked);
    if (enabled && locked == Duration.zero) _tryBiometric();
  }

  void _startLockTimer(Duration d) {
    _timer?.cancel();
    setState(() => _locked = d);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = _locked - const Duration(seconds: 1);
      if (!mounted) return;
      setState(() => _locked = left > Duration.zero ? left : Duration.zero);
      if (_locked == Duration.zero) {
        t.cancel();
        setState(() => _message = null);
      }
    });
  }

  Future<void> _tryBiometric() async {
    if (await Biometrics.authenticate('Unlock ${AppConfig.appName}')) _success();
  }

  Future<void> _onPin(String pin) async {
    final r = await _store.verifyPin(pin);
    if (!mounted) return;
    switch (r.result) {
      case PinResult.ok:
        _success();
      case PinResult.wrong:
        setState(() => _message =
            'Wrong PIN. ${r.attemptsLeft} attempt${r.attemptsLeft == 1 ? '' : 's'} left before a delay.');
      case PinResult.lockedOut:
        setState(() => _message = 'Too many attempts.');
        _startLockTimer(r.lockedFor);
    }
  }

  void _success() {
    if (!mounted) return;
    WalletSession.instance.unlocked = true;
    switch (widget.mode) {
      case UnlockMode.startup:
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
          (_) => false,
        );
      case UnlockMode.overlay:
        Navigator.of(context).pop();
      case UnlockMode.confirm:
        Navigator.of(context).pop(true);
    }
  }

  Future<void> _forgotPin() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forgot your PIN?'),
        content: const Text(
            'You can restore access with your recovery phrase. This removes the wallet from this '
            'device first. Without the recovery phrase your funds cannot be recovered.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove & restore'),
          ),
        ],
      ),
    );
    if (go != true) return;
    await _store.wipe();
    WalletSession.instance.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const ImportWalletScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final locked = _locked > Duration.zero;
    final isConfirm = widget.mode == UnlockMode.confirm;
    return PopScope(
      canPop: isConfirm,
      child: Scaffold(
        appBar: isConfirm ? AppBar(title: Text(widget.title ?? 'Confirm')) : null,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Column(children: [
                if (!isConfirm) ...[
                  const Icon(Icons.lock_outline_rounded, size: 40, color: AppColors.brand),
                  const SizedBox(height: 12),
                  const Text(AppConfig.appName,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 8),
                Text(widget.title ?? 'Enter your PIN', style: const TextStyle(color: AppColors.muted)),
                SizedBox(
                  height: 44,
                  child: Center(
                    child: Text(
                      locked ? 'Try again in ${_locked.inSeconds}s' : (_message ?? ''),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                ),
                PinPad(
                  enabled: !locked,
                  onCompleted: _onPin,
                  onBiometric: _biometric ? _tryBiometric : null,
                ),
                if (!isConfirm)
                  TextButton(onPressed: _forgotPin, child: const Text('Forgot PIN?')),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
