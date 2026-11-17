import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../app_config.dart';
import 'api_client.dart';
import 'secure_store.dart';
import 'signer.dart';
import 'tron_tx.dart';
import 'wallet_crypto.dart';

/// Checks that the two server-built transactions are exactly what the user
/// approved on the confirmation screen. Returns the locally computed
/// transaction ids (the digests to sign), keyed by purpose.
Map<String, Uint8List> verifyPreparedTransfer({
  required PreparedTransfer prepared,
  required FeeQuote quote,
  required String myAddress,
  required String network,
  required String expectedTreasury,
  DateTime? now,
}) {
  final token = AppConfig.usdtContracts[network];
  if (token == null) throw TxVerificationError('Unknown network');
  if (expectedTreasury.isEmpty || prepared.treasuryAddress != expectedTreasury) {
    throw TxVerificationError('Fee wallet does not match the server configuration');
  }
  if (prepared.transactions.length != 2) throw TxVerificationError('Unexpected transaction set');

  final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final digests = <String, Uint8List>{};
  var total = 0;
  for (final tx in prepared.transactions) {
    final raw = TronTx.hexToBytes(tx.rawDataHex);
    final digest = TronTx.txid(raw);
    if (TronTx.bytesToHex(digest) != tx.txid.toLowerCase()) {
      throw TxVerificationError('Transaction id mismatch');
    }
    final t = TronTx.parseTrc20Transfer(raw);
    if (t.owner != myAddress) throw TxVerificationError('Transaction is not from your wallet');
    if (t.token != token) throw TxVerificationError('Transaction is not for USDT');
    if (t.expirationMs <= nowMs || t.expirationMs > nowMs + 3600 * 1000) {
      throw TxVerificationError('Transaction validity window is wrong');
    }
    if (t.feeLimit > AppConfig.maxFeeLimitSun) throw TxVerificationError('Fee limit too high');

    switch (tx.purpose) {
      case 'recipient':
        if (t.to != quote.toAddress || t.amount != quote.recipientMicro) {
          throw TxVerificationError('Recipient or amount differs from what you confirmed');
        }
      case 'fee':
        if (t.to != expectedTreasury || t.amount != quote.totalFeeMicro) {
          throw TxVerificationError('Fee differs from what you confirmed');
        }
      default:
        throw TxVerificationError('Unexpected transaction');
    }
    if (digests.containsKey(tx.purpose)) throw TxVerificationError('Duplicate transaction');
    digests[tx.purpose] = digest;
    total += t.amount;
  }
  if (total != quote.amountMicro || digests.length != 2) {
    throw TxVerificationError('Totals do not match the confirmed amount');
  }
  return digests;
}

String newIdempotencyKey() {
  final r = Random.secure();
  return base64Url.encode(List<int>.generate(18, (_) => r.nextInt(256))).replaceAll('=', '');
}

/// prepare -> verify -> sign (on this phone) -> submit. Call only after the
/// user re-entered the PIN. Returns the transfer status to follow.
Future<TransferStatus> executeSend({
  required FeeQuote quote,
  required String myAddress,
  void Function(String stage)? onStage,
}) async {
  final api = ApiClient.instance;
  onStage?.call('Preparing transaction…');
  final config = await api.config(refresh: true);
  if (!config.sendingEnabled) throw TxVerificationError('Sending is not enabled on the server');
  final prepared = await api.prepareTransfer(quote.id);

  onStage?.call('Checking transaction…');
  final digests = verifyPreparedTransfer(
    prepared: prepared,
    quote: quote,
    myAddress: myAddress,
    network: config.network,
    expectedTreasury: config.treasuryAddress,
  );

  onStage?.call('Signing on this phone…');
  final phrase = await SecureStore.instance.readMnemonic();
  if (phrase == null) throw TxVerificationError('Wallet not found on this device');
  final key = await compute(derivePrivateKeyInIsolate, phrase);
  final String recipientSig;
  final String feeSig;
  try {
    recipientSig = TronTx.bytesToHex(TxSigner.sign(key, digests['recipient']!));
    feeSig = TronTx.bytesToHex(TxSigner.sign(key, digests['fee']!));
  } finally {
    key.fillRange(0, key.length, 0);
  }

  onStage?.call('Sending…');
  final idem = newIdempotencyKey();
  ApiException? last;
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      return await api.submitTransfer(
        transferId: prepared.transferId,
        idempotencyKey: idem,
        recipientSignature: recipientSig,
        feeSignature: feeSig,
      );
    } on ApiException catch (e) {
      last = e;
      // Retry only network-level failures; the idempotency key makes it safe.
      if (e.statusCode != null) rethrow;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
  throw last!;
}
