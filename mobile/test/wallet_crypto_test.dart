import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tron_wallet/core/tron_address.dart';
import 'package:tron_wallet/core/wallet_crypto.dart';

void main() {
  // Well-known BIP39 test phrase; m/44'/195'/0'/0/0.
  // Expected values were cross-checked with an independent Python
  // implementation (backend/tests/derive_vector.py).
  const phrase = 'abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon abandon abandon about';

  test('derives the standard TRON address for the test vector', () {
    expect(WalletCrypto.addressFromMnemonic(phrase), 'TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH');
  });

  test('private key 1 maps to the known address', () {
    final key = List<int>.filled(32, 0)..[31] = 1;
    expect(WalletCrypto.addressFromPrivateKey(Uint8List.fromList(key)),
        'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC');
  });

  test('generated phrases are valid 12-word phrases with valid addresses', () {
    final m = WalletCrypto.generateMnemonic();
    expect(m.split(' '), hasLength(12));
    expect(WalletCrypto.isValidMnemonic(m), isTrue);
    expect(TronAddress.isValid(WalletCrypto.addressFromMnemonic(m)), isTrue);
  });

  test('phrase normalisation and validation', () {
    expect(WalletCrypto.isValidMnemonic('  ${phrase.toUpperCase()}  '), isTrue);
    expect(WalletCrypto.isValidMnemonic(phrase.replaceFirst('about', 'abandon')), isFalse);
    expect(WalletCrypto.isValidMnemonic('abandon abandon'), isFalse);
  });
}
