import 'package:flutter_test/flutter_test.dart';
import 'package:tron_wallet/core/money.dart';

void main() {
  test('parse', () {
    expect(Usdt.tryParse('100'), 100000000);
    expect(Usdt.tryParse('99.5'), 99500000);
    expect(Usdt.tryParse('0.000001'), 1);
    for (final bad in ['', '-1', '1e5', '1.0000001', '01', '.5', '1,5', 'abc']) {
      expect(Usdt.tryParse(bad), isNull, reason: bad);
    }
  });

  test('format', () {
    expect(Usdt.format(99500000), '99.50');
    expect(Usdt.format(1234567890000), '1,234,567.89');
    expect(Usdt.format(1), '0.000001');
  });
}
