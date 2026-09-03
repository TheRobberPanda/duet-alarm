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
    this.pairId,
    this.deletedAt,
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

  /// The pair this alarm belongs to, or null while the user is solo. Set once
  /// pairing exists so the alarm is visible to both people under RLS.
  final String? pairId;

  /// Soft delete. A tombstone has to reach the other device to disarm it there;
  /// a hard delete that never syncs is an alarm that rings forever (docs/03).
  final DateTime? deletedAt;

  final DateTime updatedAt;

  bool get isDeleted => deletedAt != null;

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
    String? pairId,
    DateTime? deletedAt,
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
        pairId: pairId ?? this.pairId,
        deletedAt: deletedAt ?? this.deletedAt,
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
        'pair_id': pairId,
        'deleted_at': deletedAt?.toIso8601String(),
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
        pairId: m['pair_id'] as String?,
        deletedAt: m['deleted_at'] == null
            ? null
            : DateTime.parse(m['deleted_at'] as String),
        updatedAt: m['updated_at'] == null
            ? null
            : DateTime.parse(m['updated_at'] as String),
      );

  // ── Postgres mapping ──────────────────────────────────────────────────────
  // Deliberately explicit rather than reusing toJson(): the local store and the
  // database have different shapes (hour+minute here, a `time` column there),
  // and quietly conflating them is how sync bugs start.

  String get _localTimeSql =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:00';

  Map<String, dynamic> toDbRow(String ownerId) => {
        'id': id,
        'pair_id': pairId,
        'owner_id': ownerId,
        'label': label,
        'enabled': enabled,
        'local_time': _localTimeSql,
        'repeat_days': repeatDays,
        'one_shot_date': oneShotDate == null
            ? null
            : '${oneShotDate!.year.toString().padLeft(4, '0')}-'
                '${oneShotDate!.month.toString().padLeft(2, '0')}-'
                '${oneShotDate!.day.toString().padLeft(2, '0')}',
        'tz_mode': 'local',
        'ring_target': ringTarget.name,
        'snooze_minutes': snoozeMinutes,
        'max_snoozes': maxSnoozes,
        'deleted_at': deletedAt?.toIso8601String(),
        // updated_at is set by a database trigger, never by us: sync resolves
        // conflicts on it, and a client that could set it could win every one.
      };

  factory Alarm.fromDbRow(Map<String, dynamic> r, {String soundRef = 'default'}) {
    final t = (r['local_time'] as String).split(':');
    return Alarm(
      id: r['id'] as String,
      hour: int.parse(t[0]),
      minute: int.parse(t[1]),
      label: (r['label'] as String?) ?? '',
      enabled: (r['enabled'] as bool?) ?? true,
      repeatDays: (r['repeat_days'] as int?) ?? Repeat.none,
      oneShotDate: r['one_shot_date'] == null
          ? null
          : DateTime.parse(r['one_shot_date'] as String),
      soundRef: soundRef,
      snoozeMinutes: (r['snooze_minutes'] as int?) ?? 9,
      maxSnoozes: (r['max_snoozes'] as int?) ?? 3,
      ringTarget: RingTarget.values.firstWhere(
        (t) => t.name == r['ring_target'],
        orElse: () => RingTarget.both,
      ),
      pairId: r['pair_id'] as String?,
      deletedAt: r['deleted_at'] == null
          ? null
          : DateTime.parse(r['deleted_at'] as String),
      updatedAt: DateTime.parse(r['updated_at'] as String),
    );
  }
}

enum RingTarget {
  both('Both of us'),
  owner('Just me'),
  partner('Just them');

  const RingTarget(this.label);
  final String label;
}
