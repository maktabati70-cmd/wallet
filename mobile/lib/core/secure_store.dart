import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'pin_hasher.dart';

enum PinResult { ok, wrong, lockedOut }

class PinCheck {
  const PinCheck(this.result, {this.lockedFor = Duration.zero, this.attemptsLeft = 0});
  final PinResult result;
  final Duration lockedFor;
  final int attemptsLeft;
}

/// Everything sensitive lives in Android Keystore-backed encrypted storage.
/// Nothing here is backed up (allowBackup=false in the manifest) or sent to
/// the server.
class SecureStore {
  SecureStore._();
  static final SecureStore instance = SecureStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kMnemonic = 'wallet.mnemonic';
  static const _kAddress = 'wallet.address';
  static const _kPinHash = 'pin.hash';
  static const _kPinSalt = 'pin.salt';
  static const _kPinIter = 'pin.iterations';
  static const _kFailures = 'pin.failures';
  static const _kLockUntil = 'pin.lock_until';
  static const _kBiometric = 'settings.biometric';
  static const _kAutoLock = 'settings.autolock_seconds';

  static const int freeAttempts = 5;

  Future<bool> hasWallet() async =>
      (await _storage.read(key: _kAddress)) != null &&
      (await _storage.read(key: _kMnemonic)) != null &&
      (await _storage.read(key: _kPinHash)) != null;

  Future<void> saveWallet({required String mnemonic, required String address}) async {
    await _storage.write(key: _kMnemonic, value: mnemonic);
    await _storage.write(key: _kAddress, value: address);
  }

  Future<String?> readAddress() => _storage.read(key: _kAddress);

  /// Only call after the user re-entered their PIN.
  Future<String?> readMnemonic() => _storage.read(key: _kMnemonic);

  // ------------------------------------------------------------------ PIN
  Future<void> setPin(String pin) async {
    final salt = PinHasher.newSalt();
    const iter = PinHasher.defaultIterations;
    final hash = await compute(hashPinInIsolate, <Object>[pin, base64.encode(salt), iter]);
    await _storage.write(key: _kPinSalt, value: base64.encode(salt));
    await _storage.write(key: _kPinIter, value: '$iter');
    await _storage.write(key: _kPinHash, value: hash);
    await _storage.write(key: _kFailures, value: '0');
    await _storage.delete(key: _kLockUntil);
  }

  Future<Duration> lockRemaining() async {
    final until = int.tryParse(await _storage.read(key: _kLockUntil) ?? '');
    if (until == null) return Duration.zero;
    final left = until - DateTime.now().millisecondsSinceEpoch;
    return left > 0 ? Duration(milliseconds: left) : Duration.zero;
  }

  Future<PinCheck> verifyPin(String pin) async {
    final locked = await lockRemaining();
    if (locked > Duration.zero) return PinCheck(PinResult.lockedOut, lockedFor: locked);

    final salt = await _storage.read(key: _kPinSalt);
    final stored = await _storage.read(key: _kPinHash);
    final iter = int.tryParse(await _storage.read(key: _kPinIter) ?? '') ??
        PinHasher.defaultIterations;
    if (salt == null || stored == null) return const PinCheck(PinResult.wrong);

    final hash = await compute(hashPinInIsolate, <Object>[pin, salt, iter]);
    if (PinHasher.constantTimeEquals(hash, stored)) {
      await _storage.write(key: _kFailures, value: '0');
      await _storage.delete(key: _kLockUntil);
      return const PinCheck(PinResult.ok);
    }

    final failures = (int.tryParse(await _storage.read(key: _kFailures) ?? '') ?? 0) + 1;
    await _storage.write(key: _kFailures, value: '$failures');
    if (failures >= freeAttempts) {
      // 30 s, 60 s, 120 s ... capped at 1 hour
      final exp = (failures - freeAttempts).clamp(0, 7);
      final wait = Duration(seconds: (30 * (1 << exp)).clamp(30, 3600));
      final until = DateTime.now().add(wait).millisecondsSinceEpoch;
      await _storage.write(key: _kLockUntil, value: '$until');
      return PinCheck(PinResult.lockedOut, lockedFor: wait);
    }
    return PinCheck(PinResult.wrong, attemptsLeft: freeAttempts - failures);
  }

  // ------------------------------------------------------------------ settings
  Future<bool> biometricEnabled() async => (await _storage.read(key: _kBiometric)) == 'true';

  Future<void> setBiometricEnabled(bool value) =>
      _storage.write(key: _kBiometric, value: value ? 'true' : 'false');

  Future<int> autoLockSeconds() async =>
      int.tryParse(await _storage.read(key: _kAutoLock) ?? '') ?? 60;

  Future<void> setAutoLockSeconds(int seconds) =>
      _storage.write(key: _kAutoLock, value: '$seconds');

  /// Removes the wallet and all settings from this device.
  Future<void> wipe() => _storage.deleteAll();
}
