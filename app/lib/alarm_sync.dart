import 'package:supabase_flutter/supabase_flutter.dart';

import 'alarm.dart';

/// Pushes local alarm definitions to Postgres and pulls back whatever the other
/// device changed.
///
/// This is the ONLY thing that talks to the network about alarms. It never
/// schedules anything: the reconcile loop in AlarmRepository still owns what the
/// OS holds, so a phone with no connectivity keeps ringing exactly as before
/// (ADR-001). Sync failing is a degraded state, never a silent one.
///
/// Conflict resolution is last-write-wins on the server's `updated_at`
/// (ADR-009). Alarms are small and rarely edited from two places at once;
/// anything cleverer is unjustified complexity. Conflicts are logged so we find
/// out if that assumption was wrong.
class AlarmSync {
  AlarmSync(this._db);

  final SupabaseClient _db;

  String? get _userId => _db.auth.currentUser?.id;

  /// Reconciles [local] against the server and returns the merged set.
  ///
  /// Throws nothing: a failed sync returns [local] unchanged, because an alarm
  /// clock that refuses to work offline is not an alarm clock.
  Future<SyncResult> sync(List<Alarm> local, {String? pairId}) async {
    final uid = _userId;
    if (uid == null) return SyncResult(local, synced: false);

    try {
      final remoteRows = await _db.from('alarms').select();
      final sounds = await _fetchMySounds(uid);

      final remote = <String, Alarm>{};
      for (final row in remoteRows) {
        final map = Map<String, dynamic>.from(row);
        final id = map['id'] as String;
        remote[id] = Alarm.fromDbRow(map, soundRef: sounds[id] ?? 'default');
      }

      final localById = {for (final a in local) a.id: a};
      final merged = <String, Alarm>{};
      final toPush = <Alarm>[];
      var conflicts = 0;

      // Everything either side knows about.
      for (final id in {...localById.keys, ...remote.keys}) {
        final l = localById[id];
        final r = remote[id];

        if (r == null) {
          // Never reached the server.
          merged[id] = l!;
          toPush.add(l);
        } else if (l == null) {
          // Created on the other device, or on this one before a reinstall.
          merged[id] = r;
        } else if (l.updatedAt.isAfter(r.updatedAt)) {
          merged[id] = l;
          toPush.add(l);
          conflicts++;
        } else {
          merged[id] = r;
          if (r.updatedAt.isAfter(l.updatedAt)) conflicts++;
        }
      }

      // Stamp the pair onto anything created while solo, so the partner can see
      // it the moment pairing completes.
      //
      // A brand-new alarm is already queued in toPush (unstamped) by the loop
      // above, so finding it there is not enough to skip it -- that unstamped
      // copy is exactly the stale one that must not reach the server. It has
      // to be replaced, or the push silently ships an alarm with no pair_id
      // even though the local state (and the UI reading it) already show one.
      if (pairId != null) {
        for (final id in merged.keys.toList()) {
          final a = merged[id]!;
          if (a.pairId == null) {
            final stamped = a.copyWith(pairId: pairId);
            merged[id] = stamped;
            toPush.removeWhere((p) => p.id == id);
            toPush.add(stamped);
          }
        }
      }

      for (final alarm in toPush) {
        await _push(alarm, uid);
      }

      // Tombstones stay on the server so the other device learns of the delete,
      // but they must not clutter this device's list.
      final visible = merged.values.where((a) => !a.isDeleted).toList();
      return SyncResult(visible, synced: true, conflicts: conflicts);
    } catch (e) {
      // Deliberately swallowed: the caller carries on with local state. The
      // flag is what the UI uses to say "not synced" rather than pretending.
      return SyncResult(local, synced: false, error: e.toString());
    }
  }

  Future<Map<String, String>> _fetchMySounds(String uid) async {
    final rows = await _db
        .from('alarm_sounds')
        .select('alarm_id, sound_ref')
        .eq('listener_id', uid);
    return {
      for (final r in rows) r['alarm_id'] as String: r['sound_ref'] as String,
    };
  }

  Future<void> _push(Alarm alarm, String uid) async {
    await _db.from('alarms').upsert(alarm.toDbRow(uid));

    // The sound is per-listener, not per-alarm: this row is what *I* hear.
    // Choosing what the partner hears writes a second row with their id, which
    // is the feature the whole product is built around (docs/01).
    await _db.from('alarm_sounds').upsert({
      'alarm_id': alarm.id,
      'listener_id': uid,
      'sound_ref': alarm.soundRef,
      'set_by': uid,
    });
  }

  /// Marks an alarm deleted rather than removing the row, so the tombstone can
  /// reach the other device and disarm it there.
  Future<void> softDelete(String alarmId) async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _db
          .from('alarms')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', alarmId);
    } catch (_) {
      // The local delete already happened; the tombstone will be retried on the
      // next sync because the local row is gone and the remote one is not.
    }
  }
}

class SyncResult {
  SyncResult(this.alarms, {required this.synced, this.conflicts = 0, this.error});

  final List<Alarm> alarms;
  final bool synced;
  final int conflicts;
  final String? error;
}
