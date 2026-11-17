// Replaces the counter-app test that `flutter create` would otherwise generate.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tron_wallet/widgets/pin_pad.dart';

void main() {
  testWidgets('PinPad reports the PIN after 6 digits', (tester) async {
    String? entered;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PinPad(onCompleted: (pin) async => entered = pin),
      ),
    ));
    for (final d in ['1', '2', '3', '9', '8', '7']) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(entered, '123987');
  });

  testWidgets('PinPad ignores taps when disabled', (tester) async {
    String? entered;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PinPad(enabled: false, onCompleted: (pin) async => entered = pin),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.text('1'));
      await tester.pump();
    }
    expect(entered, isNull);
  });
}
