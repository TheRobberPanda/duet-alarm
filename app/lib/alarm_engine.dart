import 'package:flutter/services.dart';

/// Dart's view of the native alarm engine.
///
/// The contract is intentionally tiny (docs/02-architecture.md). Dart decides
/// WHAT should be armed; the native side is the only thing that talks to the OS.
class AlarmEngine {
  static const _channel = MethodChannel('com.duet.alarm/engine');

  static Future<void> arm({
    required String id,
    required DateTime fireAt,
    String label = '',
    String soundRef = 'default',
    int snoozeMinutes = 9,
    int maxSnoozes = 3,
    int wallHour = -1,
    int wallMinute = -1,
    int repeatDays = 0,
    String tzMode = 'local',
    // Null while solo. Travels with the alarm so a firing alarm knows, with no
    // Flutter engine to ask, whether it is worth reporting a ring session at
    // all -- see RingSync.kt.
    String? pairId,
  }) =>
      _channel.invokeMethod('arm', {
        'id': id,
        'fireAtUtc': fireAt.millisecondsSinceEpoch,
        'label': label,
        'soundRef': soundRef,
        // The ringing screen has no Flutter engine to consult, so the snooze
        // policy has to travel with the alarm.
        'snoozeMinutes': snoozeMinutes,
        'maxSnoozes': maxSnoozes,
        // And the wall clock travels too, so the native side can recompute the
        // instant when the device changes timezone — "07:00" means seven
        // o'clock wherever you are, which a fixed instant cannot express.
        'wallHour': wallHour,
        'wallMinute': wallMinute,
        'repeatDays': repeatDays,
        'tzMode': tzMode,
        'pairId': pairId,
      });

  /// Lets the native side act as the signed-in user with no Flutter engine
  /// running -- reporting a ring session (RingSync.kt) and, more importantly,
  /// pulling a partner's new alarms (AlarmPull.kt). Call with nulls on
  /// sign-out.
  ///
  /// [refreshToken] matters because access tokens last an hour and the native
  /// puller runs all night. Without it every overnight pull would 401 and a
  /// partner's alarm would never arrive.
  static Future<void> setAuthToken(
    String? accessToken,
    String? userId, {
    String? refreshToken,
  }) =>
      _channel.invokeMethod('setAuthToken', {
        'accessToken': accessToken,
        'userId': userId,
        'refreshToken': refreshToken,
      });

  /// The two ring colors, so the native ringing screen wears the same skins as
  /// the rest of the app. It has no Flutter engine to ask, so the choice has to
  /// be pushed down whenever it changes.
  static Future<void> setSkinColors(int mine, int partner) =>
      _channel.invokeMethod('setSkinColors', {'mine': mine, 'partner': partner});

  /// The theme's background and both display names -- the ringing screen
  /// dresses in your theme's world, puts a face on each half of the ring, and
  /// can say who woke up first when a shared ring ends (ADR-016). Pushed
  /// alongside [setSkinColors]; [partnerName] is null when solo or unpaired.
  static Future<void> setCosmetics({
    String? partnerName,
    String? myName,
    required int bgColor,
  }) =>
      _channel.invokeMethod('setCosmetics', {
        'partnerName': partnerName,
        'myName': myName,
        'bgColor': bgColor,
      });

  /// What the native LAN fast path (LanSync.kt) needs to sign its datagrams,
  /// route them to the right pair, and decide whether to honour an incoming
  /// "dismiss for both". Nulls clear it -- which is what leaving a pair or
  /// signing out should do.
  static Future<void> setPairContext({
    String? pairId,
    String? lanSecret,
    bool allowPartnerDismiss = true,
  }) =>
      _channel.invokeMethod('setPairContext', {
        'pairId': pairId,
        'lanSecret': lanSecret,
        'allowPartnerDismiss': allowPartnerDismiss,
      });

  static Future<void> disarm(String id) =>
      _channel.invokeMethod('disarm', {'id': id});

  /// What the device actually has scheduled. Read this rather than trusting a
  /// local mirror -- otherwise the health screen can confidently report an alarm
  /// that is not armed at all.
  static Future<List<ArmedAlarm>> armedAlarms() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('armedAlarms') ?? [];
    return raw
        .map((e) => ArmedAlarm.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => a.fireAt.compareTo(b.fireAt));
  }

  static Future<void> reconcile() => _channel.invokeMethod('reconcile');

  /// Asks the NATIVE puller to fetch the pair's alarms and arm them now,
  /// rather than waiting for its ten-minute heartbeat.
  ///
  /// This is the same path that runs while the app is closed (SyncReceiver ->
  /// AlarmPull), so triggering it here is how you find out whether that path
  /// works without leaving the phone alone for ten minutes. It only ever arms,
  /// never disarms -- Dart's reconcile stays authoritative.
  static Future<void> pullAlarms() => _channel.invokeMethod('pullAlarms');

  static Future<AlarmHealth> health() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('health');
    return AlarmHealth.fromMap(Map<String, dynamic>.from(raw ?? {}));
  }

  static Future<bool> openSetting(String which) async =>
      await _channel.invokeMethod<bool>('openSetting', {'which': which}) ?? false;

  /// Sounds available on this device. We ship no audio of our own — see
  /// SoundCatalog.kt for why.
  static Future<List<DeviceSound>> listSounds() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('listSounds') ?? [];
    return raw
        .map((e) => DeviceSound.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Plays on the ALARM stream, exactly as the real alarm will — previewing on
  /// the media stream would let someone choose a tone that is inaudible at 06:00.
  static Future<void> previewSound(String soundRef) =>
      _channel.invokeMethod('previewSound', {'soundRef': soundRef});

  static Future<void> stopPreview() => _channel.invokeMethod('stopPreview');
}

class ArmedAlarm {
  ArmedAlarm({required this.id, required this.fireAt, required this.label});

  final String id;
  final DateTime fireAt;
  final String label;

  factory ArmedAlarm.fromMap(Map<String, dynamic> m) => ArmedAlarm(
        id: m['id'] as String,
        fireAt: DateTime.fromMillisecondsSinceEpoch((m['fireAtUtc'] as num).toInt()),
        label: (m['label'] as String?) ?? '',
      );
}

class AlarmHealth {
  AlarmHealth({
    required this.exactAlarms,
    required this.notifications,
    required this.fullScreenIntent,
    required this.batteryUnrestricted,
    required this.manufacturer,
    required this.isAggressiveOem,
    required this.lastBootReArm,
    required this.ringLog,
    required this.missedLog,
  });

  final bool exactAlarms;
  final bool notifications;
  final bool fullScreenIntent;
  final bool batteryUnrestricted;
  final String manufacturer;
  final bool isAggressiveOem;
  final String lastBootReArm;
  final String ringLog;

  /// Alarms that were due while the app was not running. Never empty for a
  /// good reason -- every entry is an alarm that silently did not ring.
  final String missedLog;

  /// Autostart cannot be read programmatically on MIUI, so it is never counted
  /// as "passing" -- it is surfaced as an unverifiable item the user must check.
  int get problemCount => [
        exactAlarms,
        notifications,
        fullScreenIntent,
        batteryUnrestricted,
      ].where((ok) => !ok).length;

  factory AlarmHealth.fromMap(Map<String, dynamic> m) => AlarmHealth(
        exactAlarms: m['exactAlarms'] as bool? ?? false,
        notifications: m['notifications'] as bool? ?? false,
        fullScreenIntent: m['fullScreenIntent'] as bool? ?? false,
        batteryUnrestricted: m['batteryUnrestricted'] as bool? ?? false,
        manufacturer: m['manufacturer'] as String? ?? 'unknown',
        isAggressiveOem: m['isAggressiveOem'] as bool? ?? false,
        lastBootReArm: m['lastBootReArm'] as String? ?? '',
        ringLog: m['ringLog'] as String? ?? '',
        missedLog: m['missedLog'] as String? ?? '',
      );
}


class DeviceSound {
  DeviceSound({required this.ref, required this.title, required this.kind});

  final String ref;
  final String title;
  final String kind;

  bool get isDefault => ref == 'default';

  factory DeviceSound.fromMap(Map<String, dynamic> m) => DeviceSound(
        ref: m['ref'] as String,
        title: (m['title'] as String?) ?? 'Sound',
        kind: (m['kind'] as String?) ?? 'alarm',
      );
}
