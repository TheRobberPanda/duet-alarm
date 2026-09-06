import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duet/alarm.dart' show RingTarget;
import 'package:duet/alarm_editor_screen.dart' show WhoRingsPicker;

/// The who-rings circle is a pair of independent toggles: each half switches
/// its person in or out, and the alarm keeps whichever side is still lit.
/// Turning off the last lit side is refused -- the picker never emits a
/// target where nobody rings.
void main() {
  // The picker's column stretches to the full surface height, so the circle
  // sits at the top: 190x190 centred on x=400, y=95 on the default 800x600
  // test surface. Taps 60px either side of centre land cleanly in each half.
  const leftTap = Offset(340, 95);
  const rightTap = Offset(460, 95);

  testWidgets('tapping a half toggles that person', (tester) async {
    // The picker reads the target its parent handed it, so the harness must
    // rebuild on every change -- exactly what the editor's setState does.
    RingTarget target = RingTarget.both;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: WhoRingsPicker(
                target: target,
                onChanged: (t) => setState(() => target = t),
              ),
            ),
          ),
        ),
      ),
    );

    // Pump after every tap so the rebuilt tree (with the new target) is what
    // the next tap hits -- in the app the frame lands between real touches.
    await tester.tapAt(leftTap);
    await tester.pumpAndSettle();
    expect(target, RingTarget.owner, reason: 'partner toggled off -> just me');

    await tester.tapAt(leftTap);
    await tester.pumpAndSettle();
    expect(target, RingTarget.both, reason: 'partner toggled back on');

    await tester.tapAt(rightTap);
    await tester.pumpAndSettle();
    expect(target, RingTarget.partner, reason: 'you toggled off -> just them');

    await tester.tapAt(rightTap);
    await tester.pumpAndSettle();
    expect(target, RingTarget.both, reason: 'you toggled back on');
  });

  testWidgets('the last lit side never goes dark', (tester) async {
    var changes = 0;
    RingTarget target = RingTarget.owner;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: WhoRingsPicker(
              target: target,
              onChanged: (t) {
                target = t;
                changes++;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(rightTap); // would leave nobody ringing
    await tester.pumpAndSettle();
    expect(target, RingTarget.owner, reason: 'only your side is lit');
    expect(changes, 0, reason: 'the refused tap emits nothing');

    await tester.tapAt(leftTap); // adds partner -> both
    await tester.pumpAndSettle();
    expect(target, RingTarget.both);
    expect(changes, 1);
  });

  testWidgets('the caption follows the selection', (tester) async {
    RingTarget target = RingTarget.both;
    late StateSetter setter;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setter = setState;
          return MaterialApp(
            home: Scaffold(
              body: Center(
                child: WhoRingsPicker(
                  target: target,
                  onChanged: (t) => setState(() => target = t),
                ),
              ),
            ),
          );
        },
      ),
    );
    expect(find.text('Both of us'), findsOneWidget);

    setter(() => target = RingTarget.partner);
    await tester.pumpAndSettle();
    expect(find.text('Just them'), findsOneWidget);
  });
}
