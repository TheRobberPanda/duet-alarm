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
  }) =>
      _channel.invokeMethod('arm', {
        'id': id,
        'fireAtUtc': fireAt.millisecondsSinceEpoch,
        'label': label,
        'soundRef': soundRef,
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
