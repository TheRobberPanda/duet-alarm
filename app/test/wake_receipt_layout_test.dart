import 'package:duet/pair_repository.dart';
import 'package:duet/wake_receipt_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The wake receipt opens the moment a ring ends, on whatever phone the user
/// happens to own. It used to be a fixed Column with two Spacers and no scroll
/// view, so on a short screen it overflowed -- the yellow-and-black bars, in
/// place of the one celebratory moment in the app.
///
/// These sizes are the real edges: a small phone, and a normal phone whose
/// owner has turned the system font up. Both used to fail.
void main() {
  final data = WakeReceiptData(
    sessionId: 's',
    firedAt: DateTime(2026, 9, 6, 6, 14),
    iWasFirst: true,
    mySnoozes: 1,
    partnerSnoozes: 0,
    mySeconds: 120,
    partnerSeconds: 400,
    streakDays: 12,
  );

  Future<void> pumpAt(WidgetTester tester, Size size, {double textScale = 1.0}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
        child: WakeReceiptScreen(data: data, partnerName: 'Frey'),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('does not overflow on a small phone', (tester) async {
    await pumpAt(tester, const Size(320, 568));
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not overflow at a large font scale', (tester) async {
    await pumpAt(tester, const Size(392, 780), textScale: 1.6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('still centres its content on a tall screen', (tester) async {
    await pumpAt(tester, const Size(412, 915));
    expect(tester.takeException(), isNull);
    // The Spacers survive the scroll wrapper: two of them, doing the centring.
    expect(find.byType(Spacer), findsNWidgets(2));
  });
}
