import 'package:flutter_test/flutter_test.dart';
import 'package:duet/next_fire.dart';

/// The cheap half of the docs/04 test matrix: everything that does not need a
/// device. Run with `flutter test`.
void main() {
  group('one-shot', () {
    test('fires later today when the time has not passed', () {
      final now = DateTime(2026, 3, 5, 6, 0);
      expect(nextFire(now: now, hour: 6, minute: 40), DateTime(2026, 3, 5, 6, 40));
    });

    test('rolls to tomorrow when the time has passed', () {
      final now = DateTime(2026, 3, 5, 7, 0);
      expect(nextFire(now: now, hour: 6, minute: 40), DateTime(2026, 3, 6, 6, 40));
    });

    test('an explicit past date does not fire at all', () {
      final now = DateTime(2026, 3, 5, 7, 0);
      final result = nextFire(
        now: now,
        hour: 6,
        minute: 40,
        oneShotDate: DateTime(2026, 3, 1),
      );
      expect(result, isNull);
    });

    test('exactly now does not count -- strictly after', () {
      final now = DateTime(2026, 3, 5, 6, 40);
      expect(nextFire(now: now, hour: 6, minute: 40), DateTime(2026, 3, 6, 6, 40));
    });
  });

  group('repeating', () {
    test('weekday alarm on a Thursday fires Friday once Thursday has gone', () {
      final now = DateTime(2026, 3, 5, 7, 0); // Thursday
      expect(now.weekday, DateTime.thursday);
      expect(
        nextFire(now: now, hour: 6, minute: 40, repeatDays: Repeat.weekdays),
        DateTime(2026, 3, 6, 6, 40),
      );
    });

    test('weekday alarm on Friday evening skips the weekend to Monday', () {
      final now = DateTime(2026, 3, 6, 20, 0); // Friday
      expect(
        nextFire(now: now, hour: 6, minute: 40, repeatDays: Repeat.weekdays),
        DateTime(2026, 3, 9, 6, 40), // Monday
      );
    });

    test('weekend alarm from midweek lands on Saturday', () {
      final now = DateTime(2026, 3, 4, 12, 0); // Wednesday
      expect(
        nextFire(now: now, hour: 7, minute: 15, repeatDays: Repeat.weekend),
        DateTime(2026, 3, 7, 7, 15),
      );
    });

    test('daily alarm always resolves', () {
      for (var d = 1; d <= 28; d++) {
        final now = DateTime(2026, 3, d, 23, 59);
        expect(nextFire(now: now, hour: 6, minute: 40, repeatDays: Repeat.daily),
            isNotNull);
      }
    });
  });

  group('48-hour arming window', () {
    test('a daily alarm yields two fire times', () {
      final now = DateTime(2026, 3, 5, 7, 0);
      final times = fireTimesWithin(
        now: now, hour: 6, minute: 40, repeatDays: Repeat.daily,
      );
      expect(times.length, 2);
      expect(times.first, DateTime(2026, 3, 6, 6, 40));
      expect(times.last, DateTime(2026, 3, 7, 6, 40));
    });

    test('a one-shot yields exactly one', () {
      final now = DateTime(2026, 3, 5, 7, 0);
      expect(fireTimesWithin(now: now, hour: 6, minute: 40).length, 1);
    });
  });

  group('clock changes', () {
    // These run in the machine's local zone. On a UTC CI box they simply pass
    // trivially; on a developer machine in a DST zone they are a real check.
    // The device-level DST cases in docs/04 still have to be run on hardware.
    test('a repeating alarm never returns a time on the wrong day', () {
      for (var d = 1; d <= 31; d++) {
        final now = DateTime(2026, 10, d, 0, 30);
        final next = nextFire(
          now: now, hour: 2, minute: 30, repeatDays: Repeat.daily,
        );
        expect(next, isNotNull);
        expect(next!.hour, anyOf(2, 3)); // 3 when the hour was skipped forward
      }
    });

    test('never returns a time in the past', () {
      final now = DateTime(2026, 3, 29, 1, 59);
      final next = nextFire(now: now, hour: 2, minute: 0, repeatDays: Repeat.daily);
      expect(next!.isAfter(now), isTrue);
    });
  });
}
