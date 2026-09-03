import 'dart:math';

/// A RFC-4122 version-4 UUID, generated locally.
///
/// Alarm ids are client-generated so an alarm can be created, armed and rung
/// entirely offline and still merge cleanly when it reaches the server later
/// (ADR-001). They must therefore be `uuid`-shaped to match `alarms.id`.
///
/// `Random.secure()` rather than `Random()`: these ids are not secrets, but a
/// predictable generator invites collisions between two phones creating alarms
/// at the same moment, and the cost of the secure one is irrelevant here.
String newUuidV4() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));

  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1

  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

bool isUuid(String value) => _uuidPattern.hasMatch(value);
