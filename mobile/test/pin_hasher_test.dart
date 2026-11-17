import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tron_wallet/core/pin_hasher.dart';

void main() {
  test('PBKDF2-SHA256 matches RFC 7914 test vector', () {
    // RFC 7914 §11: P="passwd", S="salt", c=1, dkLen=64 (first 32 bytes here)
    final salt = Uint8List.fromList('salt'.codeUnits);
    final h = PinHasher.hash('passwd', salt, 1);
    // base64 of 55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc
    expect(h, 'VawEblbjCJ/sFpHCJUS2BflBhSFt3gRl5oudV8INrLw=');
  });

  test('different salts give different hashes', () {
    final a = PinHasher.hash('123456', PinHasher.newSalt(), 1000);
    final b = PinHasher.hash('123456', PinHasher.newSalt(), 1000);
    expect(a == b, isFalse);
    expect(PinHasher.constantTimeEquals(a, a), isTrue);
  });
}
