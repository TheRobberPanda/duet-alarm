import 'package:supabase_flutter/supabase_flutter.dart';

/// Everything the app does with accounts and pairing.
///
/// Deliberately thin: the rules live in the database (see supabase/README.md),
/// not here. This class calls RPCs and reads tables; it never decides who is
/// allowed to do what. A client that enforces its own rules is a client that
/// can be modified to stop enforcing them.
class PairRepository {
  PairRepository(this._db);

  final SupabaseClient _db;

  static SupabaseClient get _client => Supabase.instance.client;
  factory PairRepository.instance() => PairRepository(_client);

  User? get currentUser => _db.auth.currentUser;
  bool get isSignedIn => currentUser != null;

  // ── Auth ─────────────────────────────────────────────────────────────────
  // Email one-time codes rather than passwords: no password to store, reset or
  // leak, and one less field in the way of the invite flow — which is the app's
  // entire growth engine (docs/11).

  Future<void> sendOtp(String email) =>
      _db.auth.signInWithOtp(email: email.trim());

  Future<AuthResponse> verifyOtp(String email, String token) =>
      _db.auth.verifyOTP(
        email: email.trim(),
        token: token.trim(),
        type: OtpType.email,
      );

  Future<void> signOut() => _db.auth.signOut();

  /// Required by both stores, and checked by reviewers (docs/12 §2.4).
  /// The RPC dissolves the pair first so the partner is not left holding a
  /// half-deleted relationship, then deletes the auth user and cascades.
  Future<void> deleteAccount() async {
    await _db.rpc('delete_my_account');
    await _db.auth.signOut();
  }

  // ── Profile ──────────────────────────────────────────────────────────────

  Future<Profile?> myProfile() async {
    final id = currentUser?.id;
    if (id == null) return null;
    final row = await _db.from('profiles').select().eq('id', id).maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  Future<void> updateDisplayName(String name) async {
    final id = currentUser?.id;
    if (id == null) return;
    await _db.from('profiles').update({'display_name': name.trim()}).eq('id', id);
  }

  Future<void> setAllowPartnerDismiss(bool allow) async {
    final id = currentUser?.id;
    if (id == null) return;
    await _db
        .from('profiles')
        .update({'allow_partner_dismiss': allow}).eq('id', id);
  }

  /// The device's timezone, stored so the partner's screen can show "05:40 in
  /// Lisbon" and so `absolute` alarms can be resolved against the owner's zone.
  Future<void> syncTimezone(String ianaName) async {
    final id = currentUser?.id;
    if (id == null) return;
    await _db.from('profiles').update({'timezone': ianaName}).eq('id', id);
  }

  /// Your skin choice (theme.dart's `duetSkins`) -- reuses the `accent` column,
  /// which existed unused since Milestone 2. Changing it only ever paints YOUR
  /// half of every PairRing in the app, including on your partner's phone the
  /// next time their app re-reads your profile.
  Future<void> updateAccent(String skinId) async {
    final id = currentUser?.id;
    if (id == null) return;
    await _db.from('profiles').update({'accent': skinId}).eq('id', id);
  }

  /// How many alarms each of you has personally dismissed, for the home
  /// screen's rotating tip banner. Counted client-side rather than via a
  /// server aggregate: the numbers are small (a couple of alarms a day), and
  /// `ring_participants` has no surrogate key to run a Postgres `count()`
  /// against cheaply through PostgREST's filter-only interface.
  Future<Map<String, int>> dismissCounts(List<String> userIds) async {
    if (userIds.isEmpty) return {};
    final rows = await _db
        .from('ring_participants')
        .select('user_id')
        .eq('state', 'dismissed')
        .inFilter('user_id', userIds);
    final counts = {for (final id in userIds) id: 0};
    for (final row in rows) {
      final id = row['user_id'] as String;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  /// Convenience for the home screen's tip banner: resolves the pair and both
  /// dismiss counts in one call. `'partner'` is absent while solo or
  /// unpaired -- there is no one to compare with yet.
  Future<Map<String, int>> myDismissCounts() async {
    final me = currentUser?.id;
    if (me == null) return {};
    final pair = await currentPair();
    final partnerId = pair?.partner?.id;
    final byId = await dismissCounts([me, ?partnerId]);
    return {
      'mine': byId[me] ?? 0,
      if (partnerId != null) 'partner': byId[partnerId] ?? 0,
    };
  }

  /// The most recent ring the two of you have BOTH been up for, if it is
  /// fresh enough to still be "this morning" in spirit. Everything the wake
  /// receipt shows is derived from `ring_participants` (who dismissed when,
  /// how many snoozes each) and the last month of sessions (streak) -- the
  /// `wake_receipts` table itself has no writer yet, so reading it would
  /// always come back empty.
  ///
  /// "Who was first" approximated by earliest `updated_at` among dismissed
  /// participants: that column also moves on snoozes, but a final dismiss is
  /// always that participant's last touch, so the earliest final touch is
  /// genuinely the first one up.
  Future<WakeReceiptData?> latestWake() async {
    final me = currentUser?.id;
    if (me == null) return null;
    final PairState pair;
    try {
      final p = await currentPair();
      if (p == null || p.partner == null) return null;
      pair = p;
    } catch (_) {
      return null; // No pair == no shared rings; never a reason to error.
    }
    final partnerId = pair.partner!.id;

    final List<dynamic> sessions;
    try {
      sessions = await _db
          .from('ring_sessions')
          .select('id, fired_at, ring_participants(user_id, state, snooze_count, updated_at)')
          .eq('pair_id', pair.pairId)
          .order('fired_at', ascending: false)
          .limit(30);
    } catch (_) {
      return null; // Receipt is a bonus; a flaky embed must not break home.
    }
    if (sessions.isEmpty) return null;

    final latest = sessions.first as Map<String, dynamic>;
    final firedAt = DateTime.parse(latest['fired_at'] as String);

    // A receipt from a week ago is not a receipt. 20h covers an alarm any
    // time yesterday evening through this morning.
    if (DateTime.now().difference(firedAt) > const Duration(hours: 20)) {
      return null;
    }

    final parts = (latest['ring_participants'] as List).cast<Map<String, dynamic>>();
    final mine = parts.where((p) => p['user_id'] == me).toList();
    final theirs = parts.where((p) => p['user_id'] == partnerId).toList();
    if (mine.isEmpty || theirs.isEmpty) return null;
    if (mine.first['state'] != 'dismissed' || theirs.first['state'] != 'dismissed') {
      return null; // Still ringing, snoozing, or one of you slept through.
    }

    DateTime actedOn(Map<String, dynamic> p) => DateTime.parse(p['updated_at'] as String);
    final dismissed = parts.where((p) => p['state'] == 'dismissed').toList();
    final firstUpId = dismissed
        .reduce((a, b) => actedOn(a).isBefore(actedOn(b)) ? a : b)['user_id'] as String;

    // Streak: consecutive local days, counting back from the newest session,
    // where both of you ended up dismissed. Any gap or incomplete day ends
    // the run -- a streak that forgives would stop being a score.
    var streak = 0;
    DateTime? prev;
    for (final s in sessions) {
      final ps = (s['ring_participants'] as List).cast<Map<String, dynamic>>();
      if (ps.length < 2 || ps.any((p) => p['state'] != 'dismissed')) break;
      final day = DateTime.parse(s['fired_at'] as String).toLocal();
      final d = DateTime(day.year, day.month, day.day);
      if (prev != null && prev.difference(d) != const Duration(days: 1)) break;
      prev = d;
      streak++;
    }

    return WakeReceiptData(
      sessionId: latest['id'] as String,
      firedAt: firedAt,
      iWasFirst: firstUpId == me,
      mySnoozes: (mine.first['snooze_count'] as int?) ?? 0,
      partnerSnoozes: (theirs.first['snooze_count'] as int?) ?? 0,
      mySeconds: actedOn(mine.first).difference(firedAt).inSeconds.clamp(0, 24 * 3600),
      partnerSeconds: actedOn(theirs.first).difference(firedAt).inSeconds.clamp(0, 24 * 3600),
      streakDays: streak,
    );
  }

  // ── Pairing ──────────────────────────────────────────────────────────────

  /// Creates the caller's pair if they have none and returns a fresh code.
  Future<String> createInvite() async {
    final code = await _db.rpc('create_pair_invite');
    return code as String;
  }

  /// Returns the pair id. Throws a [PostgrestException] with a plain-language
  /// message on a bad code — the database is the one deciding, so the message
  /// is worth showing the user rather than replacing.
  Future<String> redeemInvite(String code) async {
    final pairId = await _db.rpc('redeem_pair_invite', params: {'p_code': code});
    return pairId as String;
  }

  /// The caller's active pair, or null. Reads through RLS, so this returns
  /// nothing for a user who is not a member — no client-side filtering needed.
  Future<PairState?> currentPair() async {
    final me = currentUser?.id;
    if (me == null) return null;

    final memberships = await _db.from('pair_members').select('pair_id');
    if (memberships.isEmpty) return null;
    final pairId = memberships.first['pair_id'] as String;

    final pair =
        await _db.from('pairs').select().eq('id', pairId).maybeSingle();
    if (pair == null || pair['status'] != 'active') return null;

    // Both members are visible under the profiles policy: self, plus anyone
    // sharing an active pair.
    final profiles = await _db.from('profiles').select();
    Profile? partner;
    for (final row in profiles) {
      if (row['id'] != me) partner = Profile.fromMap(row);
    }

    return PairState(
      pairId: pairId,
      plan: pair['plan'] as String? ?? 'free',
      partner: partner,
      lanSecret: pair['lan_secret'] as String?,
    );
  }

  /// Leaving is unilateral and non-destructive: alarms go back to being
  /// personal. The database reaps the pair once the last member is gone.
  Future<void> leavePair() async {
    final me = currentUser?.id;
    if (me == null) return;
    await _db.from('pair_members').delete().eq('user_id', me);
  }
}

class Profile {
  Profile({
    required this.id,
    required this.displayName,
    required this.timezone,
    required this.allowPartnerDismiss,
    required this.accent,
  });

  final String id;
  final String displayName;
  final String timezone;
  final bool allowPartnerDismiss;
  final String accent;

  String get shortName => displayName.trim().isEmpty ? 'Partner' : displayName.trim();
  String get initial => shortName.substring(0, 1).toUpperCase();

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        displayName: (m['display_name'] as String?) ?? '',
        timezone: (m['timezone'] as String?) ?? 'UTC',
        allowPartnerDismiss: (m['allow_partner_dismiss'] as bool?) ?? true,
        accent: (m['accent'] as String?) ?? 'teal',
      );
}

class PairState {
  PairState({
    required this.pairId,
    required this.plan,
    this.partner,
    this.lanSecret,
  });

  final String pairId;
  final String plan;

  /// Null while the pair is waiting for the second person to redeem the code.
  final Profile? partner;

  /// Signs the local-network fast path's datagrams (LanSync.kt). Readable only
  /// by the two members, and never transmitted -- only used as an HMAC key.
  final String? lanSecret;

  bool get isComplete => partner != null;
  bool get isPaid => plan == 'full';
}

/// What the wake receipt screen shows, all derived server-side-readable data.
/// See [PairRepository.latestWake] for where each field comes from and why
/// "who was first" is an approximation.
class WakeReceiptData {
  WakeReceiptData({
    required this.sessionId,
    required this.firedAt,
    required this.iWasFirst,
    required this.mySnoozes,
    required this.partnerSnoozes,
    required this.mySeconds,
    required this.partnerSeconds,
    required this.streakDays,
  });

  final String sessionId;
  final DateTime firedAt;

  /// True if your final dismiss landed before theirs.
  final bool iWasFirst;
  final int mySnoozes;
  final int partnerSnoozes;
  final int mySeconds;
  final int partnerSeconds;
  final int streakDays;
}
