import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'alarm.dart';
import 'alarm_engine.dart';
import 'next_fire.dart';

/// The app's alarm definitions, and the loop that turns them into OS alarms.
///
/// Local-only for now. When sync arrives (Milestone 3) this gains a remote
/// source, but [reconcile] does not change: it is already the single place that
/// decides what the OS should be holding, which is exactly what docs/02 asks for.
class AlarmRepository {
  AlarmRepository._();
  static final instance = AlarmRepository._();

  static const _key = 'duet_alarms_v1';

  /// How far ahead to arm. A rolling window means that if the app never runs
  /// again, two days of alarms still fire (docs/04).
  static const window = Duration(hours: 48);

  List<Alarm> _alarms = [];
  bool _loaded = false;

  List<Alarm> get alarms => List.unmodifiable(_alarms);

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      final list = jsonDecode(raw) as List<dynamic>;
      _alarms = list
          .map((e) => Alarm.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    _loaded = true;
    _sort();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(_alarms.map((a) => a.toJson()).toList()));
  }

  void _sort() => _alarms.sort((a, b) {
        final an = a.nextFireAfter(DateTime.now());
        final bn = b.nextFireAfter(DateTime.now());
        if (an == null && bn == null) return a.timeLabel.compareTo(b.timeLabel);
        if (an == null) return 1;
        if (bn == null) return -1;
        return an.compareTo(bn);
      });

  Future<void> save(Alarm alarm) async {
    await load();
    final i = _alarms.indexWhere((a) => a.id == alarm.id);
    if (i == -1) {
      _alarms.add(alarm);
    } else {
      _alarms[i] = alarm;
    }
    _sort();
    await _persist();
    await reconcile();
  }

  Future<void> delete(String id) async {
    await load();
    _alarms.removeWhere((a) => a.id == id);
    await _persist();
    await reconcile();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await load();
    final i = _alarms.indexWhere((a) => a.id == id);
    if (i == -1) return;
    _alarms[i] = _alarms[i].copyWith(enabled: enabled);
    _sort();
    await _persist();
    await reconcile();
  }

  Alarm? byId(String id) {
    for (final a in _alarms) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// The next alarm due, across all enabled alarms.
  ({Alarm alarm, DateTime at})? nextUp() {
    final now = DateTime.now();
    ({Alarm alarm, DateTime at})? best;
    for (final a in _alarms) {
      if (!a.enabled) continue;
      final at = a.nextFireAfter(now);
      if (at == null) continue;
      if (best == null || at.isBefore(best.at)) best = (alarm: a, at: at);
    }
    return best;
  }

  /// Makes the OS hold exactly the set of fire instants the definitions imply.
  ///
  /// Runs on app start, on foreground, and after every edit. It diffs against
  /// what the device actually has armed rather than a local mirror, so a
  /// disagreement between Dart and the OS gets corrected rather than persisting.
  Future<void> reconcile() async {
    await load();

    // Prune past alarms and record anything that was missed while we were not
    // running. Do this first so the missed-alarm evidence is not lost.
    await AlarmEngine.reconcile();

    final now = DateTime.now();
    final desired = <String, ({DateTime at, Alarm alarm})>{};

    for (final alarm in _alarms) {
      if (!alarm.enabled) continue;
      final times = fireTimesWithin(
        now: now,
        hour: alarm.hour,
        minute: alarm.minute,
        repeatDays: alarm.repeatDays,
        window: window,
      );
      for (final t in times) {
        // One-shot alarms with an explicit date must not be armed on the wrong
        // day: fireTimesWithin does not know about oneShotDate.
        if (!alarm.repeats) {
          final only = alarm.nextFireAfter(now);
          if (only == null || only != t) continue;
        }
        desired['${alarm.id}#${t.millisecondsSinceEpoch}'] = (at: t, alarm: alarm);
      }
    }

    final armed = await AlarmEngine.armedAlarms();
    final armedIds = armed.map((a) => a.id).toSet();

    // Anything armed that is no longer wanted -- an alarm edited, disabled or
    // deleted -- has to be cancelled, or it rings for a definition that no
    // longer exists.
    final horizon = now.add(window);
    for (final a in armed) {
      // Snooze alarms belong to a live ring session, not to a definition. The
      // native side owns them; disarming one here would cancel a snooze the
      // user just asked for.
      if (a.id.startsWith('snooze:')) continue;

      // Anything beyond our window was armed by the native side when a
      // repeating alarm fired, so that a Monday-only alarm does not need the
      // app to run before it can ring again. We cannot see those in `desired`
      // -- they are outside the horizon by definition -- so disarming them here
      // would silently undo that and reintroduce the very gap it closes.
      if (a.fireAt.isAfter(horizon)) continue;

      if (!desired.containsKey(a.id)) {
        await AlarmEngine.disarm(a.id);
      }
    }

    for (final entry in desired.entries) {
      if (armedIds.contains(entry.key)) continue;
      await AlarmEngine.arm(
        id: entry.key,
        fireAt: entry.value.at,
        label: entry.value.alarm.label,
        soundRef: entry.value.alarm.soundRef,
        snoozeMinutes: entry.value.alarm.snoozeMinutes,
        maxSnoozes: entry.value.alarm.maxSnoozes,
        wallHour: entry.value.alarm.hour,
        wallMinute: entry.value.alarm.minute,
        repeatDays: entry.value.alarm.repeatDays,
        tzMode: 'local',
      );
    }
  }

  static String newId() =>
      'a${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}
