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
    if (uid == null) {
      return SyncResult(local, synced: false, detail: 'no signed-in user');
    }

    try {
      final remoteRows = await _db.from('alarms').select();
      final prefs = await _fetchListenerPrefs(uid);

      final remote = <String, Alarm>{};
      for (final row in remoteRows) {
        final map = Map<String, dynamic>.from(row);
        final id = map['id'] as String;
        remote[id] = Alarm.fromDbRow(
          map,
          soundRef: prefs.mySounds[id] ?? 'default',
          // My own switch, falling back to the shared column for any alarm
          // that predates per-listener rows.
          enabled: prefs.myEnabled[id],
          // Theirs is display-only: it paints their half of the ring and
          // never affects what this phone arms.
          partnerEnabled: prefs.partnerEnabled[id] ?? true,
        );
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
      return SyncResult(
        visible,
        synced: true,
        conflicts: conflicts,
        // Counts only, but enough to tell "the server sent nothing" apart from
        // "the server sent it and we dropped it" -- the question that is
        // otherwise unanswerable from a phone, and the one that matters when a
        // partner's alarm does not arrive. Shown on the health screen.
        detail: 'remote ${remote.length}, local ${localById.length}, '
            'kept ${visible.length}, pushed ${toPush.length}',
      );
    } catch (e) {
      // Deliberately swallowed: the caller carries on with local state. The
      // flag is what the UI uses to say "not synced" rather than pretending.
      return SyncResult(local, synced: false, error: e.toString(), detail: 'threw');
    }
  }

  /// Every per-listener row this account can see -- mine, and (through RLS's
  /// shares_pair_with) my partner's. One round trip for both, since the ring
  /// needs to know not just what I hear but whether THEY have it switched on.
  Future<_ListenerPrefs> _fetchListenerPrefs(String uid) async {
    // Client and database never deploy at the same instant. If `enabled`
    // (migration 0010) is not there yet, fall back to the columns that always
    // have been rather than failing the whole sync over one new field -- an
    // alarm clock that stops syncing because of a pending migration is a much
    // worse outcome than one that briefly cannot tell whose switch is on.
    List<Map<String, dynamic>> rows;
    var hasEnabledColumn = true;
    try {
      rows = List<Map<String, dynamic>>.from(await _db
          .from('alarm_sounds')
          .select('alarm_id, listener_id, sound_ref, enabled'));
    } on PostgrestException {
      hasEnabledColumn = false;
      rows = List<Map<String, dynamic>>.from(
          await _db.from('alarm_sounds').select('alarm_id, listener_id, sound_ref'));
    }

    final mySounds = <String, String>{};
    final myEnabled = <String, bool>{};
    final partnerEnabled = <String, bool>{};

    for (final row in rows) {
      final alarmId = row['alarm_id'] as String;
      final enabled = (row['enabled'] as bool?) ?? true;
      if (row['listener_id'] == uid) {
        mySounds[alarmId] = (row['sound_ref'] as String?) ?? 'default';
        // Leave myEnabled unset without the column, so Alarm.fromDbRow falls
        // through to the shared alarms.enabled instead of asserting `true`
        // over the top of a genuinely switched-off alarm.
        if (hasEnabledColumn) myEnabled[alarmId] = enabled;
      } else if (hasEnabledColumn) {
        partnerEnabled[alarmId] = enabled;
      }
    }
    return _ListenerPrefs(mySounds, myEnabled, partnerEnabled);
  }

  Future<void> _push(Alarm alarm, String uid) async {
    await _db.from('alarms').upsert(alarm.toDbRow(uid));

    // The sound is per-listener, not per-alarm: this row is what *I* hear.
    // Choosing what the partner hears writes a second row with their id, which
    // is the feature the whole product is built around (docs/01). `enabled` is
    // per-listener for the same reason -- switching an alarm off here must not
    // silence it on their phone (migration 0010).
    final row = {
      'alarm_id': alarm.id,
      'listener_id': uid,
      'sound_ref': alarm.soundRef,
      'set_by': uid,
    };
    try {
      await _db.from('alarm_sounds').upsert({...row, 'enabled': alarm.enabled});
    } on PostgrestException {
      // Same reasoning as the read path: a pending migration must not cost us
      // the sound row too.
      await _db.from('alarm_sounds').upsert(row);
    }
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
  SyncResult(this.alarms,
      {required this.synced, this.conflicts = 0, this.error, this.detail});

  final List<Alarm> alarms;
  final bool synced;
  final int conflicts;
  final String? error;

  /// A short human summary of what this sync actually moved, shown on the
  /// health screen so a sync that "succeeds" but brings back nothing is
  /// visibly different from one that never ran.
  final String? detail;
}

/// One round trip's worth of per-listener rows, split by whose they are.
class _ListenerPrefs {
  _ListenerPrefs(this.mySounds, this.myEnabled, this.partnerEnabled);

  final Map<String, String> mySounds;
  final Map<String, bool> myEnabled;
  final Map<String, bool> partnerEnabled;
}
