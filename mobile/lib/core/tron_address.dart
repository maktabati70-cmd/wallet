import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:pointycastle/export.dart' show KeccakDigest;

/// TRON address helpers: Base58Check with the 0x41 prefix.
class TronAddress {
  TronAddress._();

  static const String _alphabet =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  static final BigInt _base = BigInt.from(58);
  static const int prefix = 0x41;

  static Uint8List _sha256d(List<int> data) =>
      Uint8List.fromList(sha256.convert(sha256.convert(data).bytes).bytes);

  static String base58Encode(Uint8List bytes) {
    var n = BigInt.zero;
    for (final b in bytes) {
      n = (n << 8) | BigInt.from(b);
    }
    final out = StringBuffer();
    final chars = <String>[];
    while (n > BigInt.zero) {
      chars.add(_alphabet[(n % _base).toInt()]);
      n = n ~/ _base;
    }
    for (final b in bytes) {
      if (b != 0) break;
      out.write('1');
    }
    out.writeAll(chars.reversed);
    return out.toString();
  }

  static Uint8List? base58Decode(String text) {
    var n = BigInt.zero;
    for (final ch in text.split('')) {
      final i = _alphabet.indexOf(ch);
      if (i < 0) return null;
      n = n * _base + BigInt.from(i);
    }
    final body = <int>[];
    while (n > BigInt.zero) {
      body.insert(0, (n & BigInt.from(0xff)).toInt());
      n = n >> 8;
    }
    var zeros = 0;
    while (zeros < text.length && text[zeros] == '1') {
      zeros++;
    }
    return Uint8List.fromList(List<int>.filled(zeros, 0) + body);
  }

  /// Full validation: length, prefix and checksum.
  static bool isValid(String address) {
    if (address.length != 34 || !address.startsWith('T')) return false;
    final raw = base58Decode(address);
    if (raw == null || raw.length != 25) return false;
    final payload = raw.sublist(0, 21);
    if (payload[0] != prefix) return false;
    final check = _sha256d(payload).sublist(0, 4);
    for (var i = 0; i < 4; i++) {
      if (check[i] != raw[21 + i]) return false;
    }
    return true;
  }

  static String fromPayload(Uint8List payload21) {
    final check = _sha256d(payload21).sublist(0, 4);
    return base58Encode(Uint8List.fromList(payload21 + check));
  }

  /// Address from a 65-byte uncompressed secp256k1 public key (0x04 || X || Y).
  static String fromUncompressedPublicKey(Uint8List pub65) {
    if (pub65.length != 65 || pub65[0] != 0x04) {
      throw ArgumentError('expected 65-byte uncompressed public key');
    }
    final hash = KeccakDigest(256).process(Uint8List.fromList(pub65.sublist(1)));
    final payload = Uint8List.fromList([prefix, ...hash.sublist(12)]);
    return fromPayload(payload);
  }

  /// True when two different addresses share the first and last 4 characters —
  /// the pattern used by "address poisoning" scams.
  static bool looksSimilar(String a, String b) {
    if (a == b || a.length != 34 || b.length != 34) return false;
    return a.substring(0, 5) == b.substring(0, 5) &&
        a.substring(30) == b.substring(30);
  }
}
