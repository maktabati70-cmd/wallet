import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:pointycastle/export.dart';

import '../app_config.dart';
import 'tron_address.dart';

/// Key generation and derivation. Runs only on the device; nothing here is
/// ever sent to the server.
class WalletCrypto {
  WalletCrypto._();

  /// 12-word BIP39 phrase (128 bits of entropy from a secure RNG).
  static String generateMnemonic() => bip39.generateMnemonic(strength: 128);

  static String normalize(String phrase) =>
      phrase.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');

  static bool isValidMnemonic(String phrase) {
    final words = normalize(phrase).split(' ');
    if (words.length != 12 && words.length != 24) return false;
    return bip39.validateMnemonic(words.join(' '));
  }

  static Uint8List privateKeyFromMnemonic(String phrase,
      {String path = AppConfig.derivationPath}) {
    final seed = bip39.mnemonicToSeed(normalize(phrase));
    final node = bip32.BIP32.fromSeed(seed).derivePath(path);
    final key = node.privateKey;
    if (key == null) throw StateError('derivation produced no private key');
    return key;
  }

  static Uint8List publicKeyUncompressed(Uint8List privateKey) {
    final curve = ECCurve_secp256k1();
    var d = BigInt.zero;
    for (final b in privateKey) {
      d = (d << 8) | BigInt.from(b);
    }
    final q = curve.G * d;
    if (q == null) throw StateError('invalid private key');
    return q.getEncoded(false);
  }

  static String addressFromPrivateKey(Uint8List privateKey) =>
      TronAddress.fromUncompressedPublicKey(publicKeyUncompressed(privateKey));

  static String addressFromMnemonic(String phrase) {
    final key = privateKeyFromMnemonic(phrase);
    try {
      return addressFromPrivateKey(key);
    } finally {
      key.fillRange(0, key.length, 0); // wipe key bytes from memory
    }
  }
}

/// Top-level entry point for `compute()` (runs in a background isolate).
String deriveAddressInIsolate(String phrase) => WalletCrypto.addressFromMnemonic(phrase);
