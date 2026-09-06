import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'alarm.dart';
import 'alarm_engine.dart';
import 'alarm_sync.dart';
import 'next_fire.dart';
import 'uuid.dart';

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

  /// Null when running without a backend. Everything below works either way --
  /// that is the point of ADR-001, and why the app was built local-first.
  AlarmSync? sync;
  String? pairId;

  /// Whether the last sync attempt reached the server. Surfaced in the UI so a
  /// silent failure is never mistaken for "saved".
  bool lastSyncOk = true;

  /// Why the last sync failed, or null if it did not.
  ///
  /// AlarmSync's own doc comment says "sync failing is a degraded state, never
  /// a silent one" -- but until this field the only thing that escaped was a
  /// bool, so a sync that had been failing for days looked exactly like being
  /// offline for a second, and the reason was unrecoverable. The diagnostics
  /// screen shows this verbatim.
  String? lastSyncError;

  /// What the last sync moved, or why it did not run at all. Never null after
  /// the first refresh; 'sync source not wired' means the repository was never
  /// handed an AlarmSync, which looks exactly like "nothing to do" from here
  /// and is in fact the app being unable to see the server at all.
  String lastSyncDetail = 'not attempted yet';

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

    // Alarm ids must be uuids to map onto alarms.id. Anything created before
    // sync existed gets a new one now, so an old install can still sync.
    var migrated = false;
    for (var i = 0; i < _alarms.length; i++) {
      if (!isUuid(_alarms[i].id)) {
        final old = _alarms[i];
        _alarms[i] = Alarm(
          id: newUuidV4(),
          hour: old.hour,
          minute: old.minute,
          label: old.label,
          enabled: old.enabled,
          repeatDays: old.repeatDays,
          oneShotDate: old.oneShotDate,
          soundRef: old.soundRef,
          snoozeMinutes: old.snoozeMinutes,
          maxSnoozes: old.maxSnoozes,
          ringTarget: old.ringTarget,
        );
        migrated = true;
      }
    }
    if (migrated) await _persist();

    _sort();
  }

  /// Pulls remote changes, pushes local ones, then re-arms. Safe to call with
  /// no backend: it simply reconciles what is already here.
  Future<void> refresh() async {
    await load();
    final s = sync;
    if (s == null) {
      lastSyncOk = false;
      lastSyncDetail = 'sync source not wired';
    }
    if (s != null) {
      final result = await s.sync(_alarms, pairId: pairId);
      lastSyncOk = result.synced;
      lastSyncError = result.error;
      lastSyncDetail = result.detail ?? 'no detail';
      if (!result.synced) {
        debugPrint('Duet: alarm sync failed -- ${result.error}');
      }
      if (result.synced) {
        _alarms = result.alarms;
        _sort();
        await _persist();
      }
    }
    await reconcile();
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
    // A tombstone, not a row removal: the other device has to learn of the
    // delete or it keeps ringing an alarm that no longer exists.
    await sync?.softDelete(id);
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

    // Anything armed that is no longer wanted -- an alarm edited, disabled or
    // deleted -- has to be cancelled, or it rings for a definition that no
    // longer exists.
    final horizon = now.add(window);
    for (final a in armed) {
      // Snooze alarms belong to a live ring session, not to a definition. The
      // native side owns them; disarming one here would cancel a snooze the
      // user just asked for.
      if (a.id.startsWith('snooze:')) continue;

      // Test alarms belong to the health screen's Test button, not to a
      // definition either. Before this exemption, arming a test and then
      // refreshing (which the test button itself does) disarmed the test
      // within the same second -- the button armed an alarm it then killed,
      // and no test ever rang.
      if (a.id.startsWith('test-')) continue;

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

    // Always re-armed, never skipped just because the id is already armed:
    // arm() is idempotent (AlarmManager.setAlarmClock with FLAG_UPDATE_CURRENT
    // replaces in place), and the id alone does not capture the definition --
    // a field-only change with the same fire instant, like pairId getting
    // stamped once pairing completes, used to reach native as nothing at all
    // because the id it would arm under was already present in `armed`.
    for (final entry in desired.entries) {
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
        pairId: entry.value.alarm.pairId,
      );
    }
  }

  /// A uuid, so the id is valid both locally and as `alarms.id`, and so an
  /// alarm can be created offline and merge cleanly later.
  static String newId() => newUuidV4();
}
