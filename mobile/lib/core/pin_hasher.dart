import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// PBKDF2-HMAC-SHA256 for the app PIN. The PIN only unlocks the app UI; the
/// recovery phrase itself is protected by the Android Keystore.
class PinHasher {
  PinHasher._();

  static const int defaultIterations = 100000;

  static Uint8List newSalt([int length = 16]) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => r.nextInt(256)));
  }

  static String hash(String pin, Uint8List salt, int iterations) {
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, 32));
    return base64.encode(kdf.process(Uint8List.fromList(utf8.encode(pin))));
  }

  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// `compute()` entry point: args = [pin, base64Salt, iterations].
String hashPinInIsolate(List<Object> args) => PinHasher.hash(
    args[0] as String, base64.decode(args[1] as String), args[2] as int);
