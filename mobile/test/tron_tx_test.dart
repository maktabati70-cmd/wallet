import 'package:flutter_test/flutter_test.dart';
import 'package:tron_wallet/core/tron_tx.dart';

// Built by the backend (backend/tests/test_tron_tx.py VECTOR_RAW).
const rawHex = '0a02abcd2208112233445566778840c0ef95c3b1345aae01081f12a9010a31747970652e676f6f676c6561'
    '7069732e636f6d2f70726f746f636f6c2e54726967676572536d617274436f6e747261637412740a1541'
    'c8599111f29c1e1e061265b4af93ea1f274ad78a121541eca9bc828a3005b9a3b909f2cc5c2a54794de0'
    '5f2244a9059cbb0000000000000000000000007e5f4552091a69125d5dfcb7b8c2659029395bdf000000'
    '0000000000000000000000000000000000000000000000000005c756f070fba0f1c2b134900180b48913';

void main() {
  test('decodes the backend-built TRC20 transfer', () {
    final raw = TronTx.hexToBytes(rawHex);
    final t = TronTx.parseTrc20Transfer(raw);
    expect(t.owner, 'TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH');
    expect(t.token, 'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf');
    expect(t.to, 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC');
    expect(t.amount, 96950000);
    expect(t.expirationMs, 1800000000000 + 600000);
    expect(t.feeLimit, 40000000);
    expect(TronTx.bytesToHex(TronTx.txid(raw)),
        'fc5732905d0068d9d21c34451cd1c028bb286ae8919ffeb7602aee18f03a6655');
  });

  test('rejects approve() and tampered data', () {
    final approve = rawHex.replaceFirst('a9059cbb', '095ea7b3');
    expect(() => TronTx.parseTrc20Transfer(TronTx.hexToBytes(approve)),
        throwsA(isA<TxVerificationError>()));
    expect(() => TronTx.parseTrc20Transfer(TronTx.hexToBytes(rawHex.substring(0, 100))),
        throwsA(isA<TxVerificationError>()));
  });
}
