import 'next_fire.dart';

/// An alarm definition, as the user sees it.
///
/// The field names deliberately mirror `public.alarms` in the database
/// (supabase/migrations/0001_core_schema.sql) so that when sync arrives it is a
/// straight mapping rather than a translation layer.
///
/// Stored as wall-clock time + repeat rule, NEVER as a UTC instant — see
/// docs/04. The fire instants are derived at arm time.
class Alarm {
  Alarm({
    required this.id,
    required this.hour,
    required this.minute,
    this.label = '',
    this.enabled = true,
    this.repeatDays = Repeat.none,
    this.oneShotDate,
    this.soundRef = 'default',
    this.snoozeMinutes = 9,
    this.maxSnoozes = 3,
    this.ringTarget = RingTarget.both,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final int hour;
  final int minute;
  final String label;
  final bool enabled;

  /// Bitmask, Mon = 1<<0 … Sun = 1<<6. Zero means one-shot.
  final int repeatDays;
  final DateTime? oneShotDate;

  /// `default` = the device's alarm tone. `device:<uri>` = a specific ringtone
  /// on this phone. Using the phone's own tones means shipping no audio files,
  /// which sidesteps the sound-licensing problem in docs/12 §3.7 entirely.
  final String soundRef;

  final int snoozeMinutes;
  final int maxSnoozes;

  /// Who this alarm wakes. Meaningful only once pairing is live; stored now so
  /// the model does not have to change later.
  final RingTarget ringTarget;

  final DateTime updatedAt;

  bool get repeats => repeatDays != Repeat.none;
  bool get snoozeAllowed => maxSnoozes > 0;

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// "Mon – Fri", "Every day", "Sat, Sun", "Once, Fri 14 Mar".
  String get scheduleLabel {
    if (!repeats) {
      final d = oneShotDate;
      if (d == null) return 'Once';
      const months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
      const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
      return 'Once · ${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
    }
    if (repeatDays == Repeat.daily) return 'Every day';
    if (repeatDays == Repeat.weekdays) return 'Mon – Fri';
    if (repeatDays == Repeat.weekend) return 'Sat, Sun';

    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final on = <String>[];
    for (var i = 0; i < 7; i++) {
      if (repeatDays & (1 << i) != 0) on.add(names[i]);
    }
    return on.join(', ');
  }

  DateTime? nextFireAfter(DateTime now) => nextFire(
        now: now,
        hour: hour,
        minute: minute,
        repeatDays: repeatDays,
        oneShotDate: oneShotDate,
      );

  Alarm copyWith({
    int? hour,
    int? minute,
    String? label,
    bool? enabled,
    int? repeatDays,
    DateTime? oneShotDate,
    bool clearOneShotDate = false,
    String? soundRef,
    int? snoozeMinutes,
    int? maxSnoozes,
    RingTarget? ringTarget,
  }) =>
      Alarm(
        id: id,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        label: label ?? this.label,
        enabled: enabled ?? this.enabled,
        repeatDays: repeatDays ?? this.repeatDays,
        oneShotDate:
            clearOneShotDate ? null : (oneShotDate ?? this.oneShotDate),
        soundRef: soundRef ?? this.soundRef,
        snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
        maxSnoozes: maxSnoozes ?? this.maxSnoozes,
        ringTarget: ringTarget ?? this.ringTarget,
        updatedAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'hour': hour,
        'minute': minute,
        'label': label,
        'enabled': enabled,
        'repeat_days': repeatDays,
        'one_shot_date': oneShotDate?.toIso8601String(),
        'sound_ref': soundRef,
        'snooze_minutes': snoozeMinutes,
        'max_snoozes': maxSnoozes,
        'ring_target': ringTarget.name,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Alarm.fromJson(Map<String, dynamic> m) => Alarm(
        id: m['id'] as String,
        hour: m['hour'] as int,
        minute: m['minute'] as int,
        label: (m['label'] as String?) ?? '',
        enabled: (m['enabled'] as bool?) ?? true,
        repeatDays: (m['repeat_days'] as int?) ?? Repeat.none,
        oneShotDate: m['one_shot_date'] == null
            ? null
            : DateTime.parse(m['one_shot_date'] as String),
        soundRef: (m['sound_ref'] as String?) ?? 'default',
        snoozeMinutes: (m['snooze_minutes'] as int?) ?? 9,
        maxSnoozes: (m['max_snoozes'] as int?) ?? 3,
        ringTarget: RingTarget.values.firstWhere(
          (t) => t.name == m['ring_target'],
          orElse: () => RingTarget.both,
        ),
        updatedAt: m['updated_at'] == null
            ? null
            : DateTime.parse(m['updated_at'] as String),
      );
}

enum RingTarget {
  both('Both of us'),
  owner('Just me'),
  partner('Just them');

  const RingTarget(this.label);
  final String label;
}
