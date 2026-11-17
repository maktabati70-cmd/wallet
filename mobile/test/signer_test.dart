import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tron_wallet/core/signer.dart';
import 'package:tron_wallet/core/tron_tx.dart';
import 'package:tron_wallet/core/wallet_crypto.dart';

Uint8List h(String s) => Uint8List.fromList(sha256.convert(utf8.encode(s)).bytes);

void main() {
  test('RFC 6979 known vector (key = 1, "Satoshi Nakamoto")', () {
    final key = Uint8List(32)..[31] = 1;
    final sig = TronTx.bytesToHex(TxSigner.sign(key, h('Satoshi Nakamoto')));
    expect(sig.substring(0, 64), '934b1ea10a4b3c1757e2b0c017d0b6143ce3c9a7e6a4a49860d7a6ab210ee3d8');
    expect(sig.substring(64, 128), '2442ce9d2b916064108014783e923ec36b49743e2ffa1c4496f01a512aafd9e5');
  });

  test('identical to the backend signer (cross-platform vector)', () {
    final sig = TronTx.bytesToHex(TxSigner.sign(h('test'), h('hello')));
    expect(
        sig,
        'd10a1041283dd120e8b539fad17b8c687dbb2a1792bf814409d15b6a95c921c0'
        '3327a135389e8028013a33888ac4a20fe72793e0eff71cff9edc87b290b734451b');
  });

  test('signature recovers to the signing key', () {
    final key = h('k');
    final digest = h('m');
    final sig = TxSigner.sign(key, digest);
    expect(TxSigner.recoverPublicKey(digest, sig), WalletCrypto.publicKeyUncompressed(key));
  });
}
