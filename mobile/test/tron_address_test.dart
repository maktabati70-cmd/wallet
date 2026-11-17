import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tron_wallet/core/tron_address.dart';

void main() {
  const vector = 'TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH';

  test('valid addresses pass full checksum validation', () {
    expect(TronAddress.isValid(vector), isTrue);
    expect(TronAddress.isValid('TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t'), isTrue);
  });

  test('invalid addresses are rejected', () {
    expect(TronAddress.isValid('TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdJ'), isFalse); // checksum
    expect(TronAddress.isValid('TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYd'), isFalse); // length
    expect(TronAddress.isValid('1BoatSLRHtKNngkdXEeobR76b53LETtpyT'), isFalse); // bitcoin
    expect(TronAddress.isValid('TUEZSdKsoDHQMeZwihtdoBiN46zxhGWY0H'), isFalse); // bad char
    expect(TronAddress.isValid(''), isFalse);
  });

  test('base58 round trip keeps leading zeros', () {
    final data = Uint8List.fromList([0, 0, 1, 2, 255]);
    expect(TronAddress.base58Decode(TronAddress.base58Encode(data)), data);
  });

  test('look-alike detection', () {
    const a = 'TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH';
    const b = 'TUEZSxxxxxxxxxxxxxxxxxxxxxxxxGWYdH';
    expect(TronAddress.looksSimilar(a, b), isTrue);
    expect(TronAddress.looksSimilar(a, a), isFalse);
    expect(TronAddress.looksSimilar(a, 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t'), isFalse);
  });
}
