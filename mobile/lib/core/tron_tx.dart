import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

import 'tron_address.dart';

/// Decodes the raw TRON transactions the server asks us to sign and checks
/// every byte BEFORE signing. The phone never signs something it has not
/// fully understood: one TRC20 `transfer(address,uint256)`, from our address,
/// on the expected token contract, to the expected address, for the expected
/// amount. The transaction id (the thing we sign) is computed here, not taken
/// from the server.
class Trc20Tx {
  Trc20Tx({
    required this.owner,
    required this.token,
    required this.to,
    required this.amount,
    required this.expirationMs,
    required this.feeLimit,
  });

  final String owner;
  final String token;
  final String to;
  final int amount;
  final int expirationMs;
  final int feeLimit;
}

class TxVerificationError implements Exception {
  TxVerificationError(this.message);
  final String message;
  @override
  String toString() => message;
}

class _Field {
  _Field(this.number, this.wire, this.intValue, this.bytes);
  final int number;
  final int wire;
  final int intValue;
  final Uint8List? bytes;
}

class TronTx {
  TronTx._();

  static const _triggerSmartContract = 31;
  static const _typeUrl = 'type.googleapis.com/protocol.TriggerSmartContract';
  static const _transferSelector = [0xa9, 0x05, 0x9c, 0xbb];

  static Uint8List txid(Uint8List raw) => Uint8List.fromList(sha256.convert(raw).bytes);

  static Uint8List hexToBytes(String hex) {
    if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(hex)) {
      throw TxVerificationError('Invalid hex data from server');
    }
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(2 * i, 2 * i + 2), radix: 16);
    }
    return out;
  }

  static String bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<_Field> _parse(Uint8List buf) {
    final out = <_Field>[];
    var i = 0;
    (int, int) varint() {
      var result = 0;
      var shift = 0;
      while (true) {
        if (i >= buf.length || shift > 63) throw TxVerificationError('Malformed transaction');
        final b = buf[i++];
        result |= (b & 0x7f) << shift;
        if (b & 0x80 == 0) return (result, i);
        shift += 7;
      }
    }

    while (i < buf.length) {
      final (key, _) = varint();
      final number = key >> 3;
      final wire = key & 7;
      if (wire == 0) {
        final (v, _) = varint();
        out.add(_Field(number, wire, v, null));
      } else if (wire == 2) {
        final (len, _) = varint();
        if (len < 0 || i + len > buf.length) throw TxVerificationError('Malformed transaction');
        out.add(_Field(number, wire, 0, Uint8List.sublistView(buf, i, i + len)));
        i += len;
      } else {
        throw TxVerificationError('Unsupported transaction encoding');
      }
    }
    return out;
  }

  static Map<int, _Field> _single(List<_Field> fields, Set<int> allowed) {
    final map = <int, _Field>{};
    for (final f in fields) {
      if (!allowed.contains(f.number) || map.containsKey(f.number)) {
        throw TxVerificationError('Unexpected field in transaction');
      }
      map[f.number] = f;
    }
    return map;
  }

  /// Strictly decodes a raw transaction that must be one TRC20 transfer().
  static Trc20Tx parseTrc20Transfer(Uint8List raw) {
    final top = _single(_parse(raw), {1, 4, 8, 11, 14, 18});
    final contract = top[11]?.bytes;
    if (contract == null) throw TxVerificationError('No contract in transaction');
    final c = _single(_parse(contract), {1, 2});
    if (c[1]?.intValue != _triggerSmartContract || c[2]?.bytes == null) {
      throw TxVerificationError('Not a token transfer');
    }
    final any = _single(_parse(c[2]!.bytes!), {1, 2});
    if (String.fromCharCodes(any[1]?.bytes ?? const []) != _typeUrl || any[2]?.bytes == null) {
      throw TxVerificationError('Not a token transfer');
    }
    // owner(1), contract(2), data(4) only — no TRX value attached
    final t = _single(_parse(any[2]!.bytes!), {1, 2, 4});
    final data = t[4]?.bytes;
    if (data == null || data.length != 68) throw TxVerificationError('Not a token transfer');
    for (var k = 0; k < 4; k++) {
      if (data[k] != _transferSelector[k]) throw TxVerificationError('Not a transfer() call');
    }
    for (var k = 4; k < 16; k++) {
      if (data[k] != 0) throw TxVerificationError('Bad recipient encoding');
    }
    var amount = 0;
    for (var k = 36; k < 68; k++) {
      if ((k < 60 && data[k] != 0) || (k == 60 && data[k] >= 0x80)) {
        throw TxVerificationError('Amount too large');
      }
      amount = (amount << 8) | data[k];
    }
    String addr(Uint8List? b) {
      if (b == null || b.length != 21 || b[0] != 0x41) throw TxVerificationError('Bad address');
      return TronAddress.fromPayload(b);
    }

    return Trc20Tx(
      owner: addr(t[1]?.bytes),
      token: addr(t[2]?.bytes),
      to: addr(Uint8List.fromList([0x41, ...data.sublist(16, 36)])),
      amount: amount,
      expirationMs: top[8]?.intValue ?? 0,
      feeLimit: top[18]?.intValue ?? 0,
    );
  }
}
