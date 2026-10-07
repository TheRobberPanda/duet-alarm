import 'package:flutter_test/flutter_test.dart';
import 'package:duet/alarm.dart';

void main() {
  test('wake later shifts only the named listener', () {
    final a = Alarm(id: 'x', hour: 7, minute: 0, wakeLaterId: 'her');
    expect(a.forListener('me').timeLabel, '07:00');
    expect(a.forListener('her').timeLabel, '07:15');
  });

  test('crossing midnight moves repeat days and one-shot date', () {
    final sun = 1 << 6, mon = 1 << 0, tue = 1 << 1;
    final a = Alarm(
        id: 'x', hour: 23, minute: 50, repeatDays: sun | mon, wakeLaterId: 'her');
    final s = a.forListener('her');
    expect(s.timeLabel, '00:05');
    expect(s.repeatDays, mon | tue);

    final once = Alarm(
        id: 'y', hour: 23, minute: 55, oneShotDate: DateTime(2026, 9, 30), wakeLaterId: 'her');
    expect(once.forListener('her').oneShotDate, DateTime(2026, 10, 1));
  });

  test('ring target is read from each phone\'s side', () {
    final justMe = Alarm(
        id: 'z', hour: 7, minute: 0, ownerId: 'him', ringTarget: RingTarget.owner);
    expect(justMe.ringsFor('him'), isTrue);
    expect(justMe.ringsFor('her'), isFalse);
    expect(justMe.targetFor('her'), RingTarget.partner);

    final justThem = Alarm(
        id: 'z', hour: 7, minute: 0, ownerId: 'him', ringTarget: RingTarget.partner);
    expect(justThem.ringsFor('him'), isFalse);
    expect(justThem.ringsFor('her'), isTrue);

    // Not synced yet: made on this phone, so it is ours.
    expect(Alarm(id: 'n', hour: 7, minute: 0, ringTarget: RingTarget.owner)
        .ringsFor('anyone'), isTrue);
  });
}
