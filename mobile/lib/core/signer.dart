import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:pointycastle/export.dart';

/// secp256k1 ECDSA signing in TRON's format: r(32) || s(32) || v(27 + recId).
/// Deterministic (RFC 6979) and low-s, so the same key and digest always give
/// the same signature (cross-checked with the backend's Python implementation).
class TxSigner {
  TxSigner._();

  static final ECCurve_secp256k1 _curve = ECCurve_secp256k1();

  static BigInt _toBig(List<int> bytes) {
    var r = BigInt.zero;
    for (final b in bytes) {
      r = (r << 8) | BigInt.from(b);
    }
    return r;
  }

  static Uint8List _to32(BigInt v) {
    final out = Uint8List(32);
    var x = v;
    for (var i = 31; i >= 0; i--) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x = x >> 8;
    }
    return out;
  }

  static ECPoint? _recover(Uint8List digest, BigInt r, BigInt s, int recId) {
    final n = _curve.n;
    final enc = Uint8List(33)
      ..[0] = 0x02 + recId
      ..setRange(1, 33, _to32(r));
    final ECPoint? bigR;
    try {
      bigR = _curve.curve.decodePoint(enc);
    } catch (_) {
      return null;
    }
    if (bigR == null) return null;
    final e = _toBig(digest) % n;
    final sR = bigR * s;
    final eG = _curve.G * ((n - e) % n);
    if (sR == null || eG == null) return null;
    final sum = sR + eG;
    return sum == null ? null : sum * r.modInverse(n);
  }

  /// Signs a 32-byte digest (a TRON transaction id).
  static Uint8List sign(Uint8List privateKey, Uint8List digest) {
    if (digest.length != 32) throw ArgumentError('digest must be 32 bytes');
    final d = _toBig(privateKey);
    final signer = ECDSASigner(null, HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(ECPrivateKey(d, _curve)));
    final sig = signer.generateSignature(digest) as ECSignature;
    final n = _curve.n;
    final s = sig.s.compareTo(n >> 1) > 0 ? n - sig.s : sig.s;

    final pub = (_curve.G * d)!.getEncoded(false);
    for (var recId = 0; recId < 2; recId++) {
      final q = _recover(digest, sig.r, s, recId);
      if (q != null && listEquals(q.getEncoded(false), pub)) {
        return Uint8List.fromList([..._to32(sig.r), ..._to32(s), 27 + recId]);
      }
    }
    throw StateError('could not compute recovery id');
  }

  /// Uncompressed public key recovered from a signature (for tests/checks).
  static Uint8List? recoverPublicKey(Uint8List digest, Uint8List signature) {
    if (signature.length != 65) return null;
    final r = _toBig(signature.sublist(0, 32));
    final s = _toBig(signature.sublist(32, 64));
    final v = signature[64];
    final q = _recover(digest, r, s, v >= 27 ? v - 27 : v);
    return q?.getEncoded(false);
  }
}
