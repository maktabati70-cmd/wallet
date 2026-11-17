import 'package:flutter_test/flutter_test.dart';
import 'package:tron_wallet/core/api_client.dart';
import 'package:tron_wallet/core/send_flow.dart';
import 'package:tron_wallet/core/tron_tx.dart';

import 'tron_tx_test.dart' show rawHex;

const me = 'TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH';
const to = 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC';

FeeQuote quote({int recipient = 96950000, int fee = 0}) => FeeQuote({
      'quote_id': 'q', 'expires_at': '2030-01-01T00:00:00Z', 'from_address': me, 'to_address': to,
      'amount': '', 'amount_micro': recipient + fee, 'recipient_micro': recipient,
      'total_fee_micro': fee, 'service_fee': '', 'service_fee_percent': '', 'resource_fee': '',
      'total_fee': '', 'recipient_receives': '', 'recipient_is_new': false,
      'resource_fee_disclosure': '', 'sending_enabled': true,
    });

PreparedTransfer prepared(List<Map<String, Object>> txs) =>
    PreparedTransfer({'transfer_id': 't', 'treasury_address': to, 'transactions': txs});

void main() {
  final raw = TronTx.hexToBytes(rawHex);
  final txid = TronTx.bytesToHex(TronTx.txid(raw));
  final at = DateTime.fromMillisecondsSinceEpoch(1800000000000);

  test('rejects a recipient amount different from the confirmed quote', () {
    final p = prepared([
      {'purpose': 'recipient', 'raw_data_hex': rawHex, 'txid': txid, 'to': to, 'amount_micro': 1},
      {'purpose': 'fee', 'raw_data_hex': rawHex, 'txid': txid, 'to': to, 'amount_micro': 1},
    ]);
    expect(
      () => verifyPreparedTransfer(prepared: p, quote: quote(recipient: 1), myAddress: me,
          network: 'nile', expectedTreasury: to, now: at),
      throwsA(isA<TxVerificationError>()),
    );
  });

  test('rejects a server-supplied txid that does not match the bytes', () {
    final p = prepared([
      {'purpose': 'recipient', 'raw_data_hex': rawHex, 'txid': '00' * 32, 'to': to, 'amount_micro': 1},
      {'purpose': 'fee', 'raw_data_hex': rawHex, 'txid': txid, 'to': to, 'amount_micro': 1},
    ]);
    expect(
      () => verifyPreparedTransfer(prepared: p, quote: quote(), myAddress: me,
          network: 'nile', expectedTreasury: to, now: at),
      throwsA(isA<TxVerificationError>()),
    );
  });

  test('rejects a transaction from another wallet', () {
    final p = prepared([
      {'purpose': 'recipient', 'raw_data_hex': rawHex, 'txid': txid, 'to': to, 'amount_micro': 1},
      {'purpose': 'fee', 'raw_data_hex': rawHex, 'txid': txid, 'to': to, 'amount_micro': 1},
    ]);
    expect(
      () => verifyPreparedTransfer(prepared: p, quote: quote(), myAddress: to,
          network: 'nile', expectedTreasury: to, now: at),
      throwsA(isA<TxVerificationError>()),
    );
  });

  test('personal mode: exactly one transfer, no fee', () {
    final ok = prepared([
      {'purpose': 'recipient', 'raw_data_hex': rawHex, 'txid': txid, 'to': to, 'amount_micro': 96950000},
    ]);
    final digests = verifyPreparedTransfer(prepared: ok, quote: quote(), myAddress: me,
        network: 'nile', expectedTreasury: '', now: at);
    expect(digests.keys, ['recipient']);

    final extra = prepared([
      {'purpose': 'recipient', 'raw_data_hex': rawHex, 'txid': txid, 'to': to, 'amount_micro': 96950000},
      {'purpose': 'fee', 'raw_data_hex': rawHex, 'txid': txid, 'to': to, 'amount_micro': 0},
    ]);
    expect(
      () => verifyPreparedTransfer(prepared: extra, quote: quote(), myAddress: me,
          network: 'nile', expectedTreasury: '', now: at),
      throwsA(isA<TxVerificationError>()),
    );
  });
}
