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

  /// Lets a firing alarm report a ring session as the signed-in user, with no
  /// Flutter engine running. Call with nulls on sign-out.
  static Future<void> setAuthToken(String? accessToken, String? userId) =>
      _channel.invokeMethod('setAuthToken', {
        'accessToken': accessToken,
        'userId': userId,
      });

  /// The two ring colors, so the native ringing screen wears the same skins as
  /// the rest of the app. It has no Flutter engine to ask, so the choice has to
  /// be pushed down whenever it changes.
  static Future<void> setSkinColors(int mine, int partner) =>
      _channel.invokeMethod('setSkinColors', {'mine': mine, 'partner': partner});

  /// The theme's background and the partner's display name -- the ringing
  /// screen dresses in your theme's world and can say who woke up first when
  /// a shared ring ends (ADR-016). Pushed alongside [setSkinColors]; the
  /// name is null when solo or unpaired.
  static Future<void> setCosmetics({String? partnerName, required int bgColor}) =>
      _channel.invokeMethod('setCosmetics', {
        'partnerName': partnerName,
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
