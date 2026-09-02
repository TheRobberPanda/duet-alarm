/// Pure alarm scheduling maths. No Flutter, no Android, no clock of its own --
/// `now` is always passed in.
///
/// This is deliberately dependency-free so the whole DST/timezone test matrix
/// from docs/04-alarm-engine.md runs as fast unit tests on Linux, with no device
/// and no emulator. Timezone bugs surface twice a year and are brutal to debug
/// in the wild; they are cheap to pin down here.
library;

/// Bitmask: Monday = 1 << 0 ... Sunday = 1 << 6. Zero means a one-shot alarm.
class Repeat {
  static const none = 0;
  static const monday = 1 << 0;
  static const tuesday = 1 << 1;
  static const wednesday = 1 << 2;
  static const thursday = 1 << 3;
  static const friday = 1 << 4;
  static const saturday = 1 << 5;
  static const sunday = 1 << 6;

  static const weekdays = monday | tuesday | wednesday | thursday | friday;
  static const weekend = saturday | sunday;
  static const daily = weekdays | weekend;

  /// Dart's [DateTime.weekday] is 1 (Mon) to 7 (Sun).
  static int bitFor(int dartWeekday) => 1 << (dartWeekday - 1);

  static bool includes(int mask, int dartWeekday) =>
      mask & bitFor(dartWeekday) != 0;
}

/// The next moment an alarm at [hour]:[minute] should ring, strictly after [now].
///
/// Returns null for a one-shot whose time has already passed.
///
/// Local wall-clock semantics: 07:00 means 07:00 wherever the device is, which
/// is what people expect from an alarm clock. Storing a bare UTC instant instead
/// is the classic mistake -- it breaks the moment the user travels or the clocks
/// change.
DateTime? nextFire({
  required DateTime now,
  required int hour,
  required int minute,
  int repeatDays = Repeat.none,
  DateTime? oneShotDate,
}) {
  if (repeatDays == Repeat.none) {
    final day = oneShotDate ?? now;
    final candidate = DateTime(day.year, day.month, day.day, hour, minute);
    if (candidate.isAfter(now)) return candidate;
    // No explicit date given and today's time has gone -- roll to tomorrow.
    if (oneShotDate == null) {
      final t = now.add(const Duration(days: 1));
      return DateTime(t.year, t.month, t.day, hour, minute);
    }
    return null;
  }

  // Walk forward day by day. Eight iterations covers a full week plus the case
  // where today's slot has already passed.
  for (var i = 0; i < 8; i++) {
    final day = now.add(Duration(days: i));
    if (!Repeat.includes(repeatDays, day.weekday)) continue;

    final candidate = DateTime(day.year, day.month, day.day, hour, minute);

    // Spring forward: 02:30 does not exist on the transition day, and Dart
    // normalises it to 03:30. That is the correct behaviour for an alarm -- it
    // fires as soon as the wall clock passes the requested time rather than
    // being skipped entirely -- but assert the day is right, or a normalised
    // time could silently land on the following day.
    if (candidate.day != day.day) continue;

    if (candidate.isAfter(now)) return candidate;
  }
  return null;
}

/// Every fire instant within the next [window]. The engine arms a rolling
/// 48 hours rather than only the next occurrence, so that if the app never runs
/// again, two days of alarms still ring.
List<DateTime> fireTimesWithin({
  required DateTime now,
  required int hour,
  required int minute,
  int repeatDays = Repeat.none,
  Duration window = const Duration(hours: 48),
}) {
  final end = now.add(window);
  final out = <DateTime>[];
  var cursor = now;

  while (out.length < 16) {
    final next = nextFire(
      now: cursor,
      hour: hour,
      minute: minute,
      repeatDays: repeatDays,
    );
    if (next == null || next.isAfter(end)) break;
    out.add(next);
    cursor = next.add(const Duration(minutes: 1));
    if (repeatDays == Repeat.none) break;
  }
  return out;
}
