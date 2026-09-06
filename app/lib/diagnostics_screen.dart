import 'package:flutter/material.dart';

import 'alarm_engine.dart';
import 'alarm_repository.dart';
import 'theme.dart';

/// Alarm health and the evidence behind it.
///
/// Not a debug screen — this is a shipping feature. On an aggressive OEM it is
/// the difference between an alarm that rings and one that silently does not,
/// and it is what turns a missed alarm into something the user can fix rather
/// than something they discover by oversleeping (docs/01, docs/12 §3.1).
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  AlarmHealth? _health;
  int _armedCount = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// The native puller, on demand. The two-second wait is the request itself:
  /// AlarmPull hands off to a background thread and returns immediately, so
  /// re-reading the armed count any sooner just shows the old one.
  Future<void> _pullNow() async {
    await AlarmEngine.pullAlarms();
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    showDuetSnackBar(context, 'Pulled. $_armedCount fire times armed.',
        icon: Icons.cloud_done_outlined);
  }

  Future<void> _refresh() async {
    // refresh(), not reconcile(): this screen's whole job is to report on the
    // sync, and reconcile() never touches it -- so the numbers below used to
    // describe whatever the home screen last did, which is not evidence.
    await AlarmRepository.instance.refresh();
    final health = await AlarmEngine.health();
    final armed = await AlarmEngine.armedAlarms();
    if (mounted) {
      setState(() { _health = health; _armedCount = armed.length; });
    }
  }

  Future<void> _testIn(Duration d) async {
    await AlarmEngine.arm(
      // The fired-id shape a real alarm has, '<id>#<instant>', not a bare one.
      // The ringing screen splits on '#' to derive the ring session, so a test
      // without it silently exercised none of the partner code -- no avatars,
      // no awareness strip, no dismiss-for-both. A test alarm that skips the
      // half of the screen most likely to break is not a test.
      id: 'test-${DateTime.now().millisecondsSinceEpoch}'
          '#${DateTime.now().add(d).millisecondsSinceEpoch}',
      fireAt: DateTime.now().add(d),
      label: 'Test alarm',
      pairId: AlarmRepository.instance.pairId,
    );
    await _refresh();
    if (mounted) {
      showDuetSnackBar(context, 'Test alarm set for ${d.inSeconds}s from now',
          icon: Icons.alarm_rounded);
    }
  }

  // System monospace: evidence text is machine output and should look like
  // machine output, but it still sits in a plum field -- so it goes on a dark
  // inset slab rather than floating raw.
  TextStyle _mono(Color color) => TextStyle(
      color: color, fontSize: 11.5, height: 1.55, fontFamily: 'monospace');

  Widget _monoSlab(String text, Color color) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: SkinColors.instance.pal.bgDeep.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SkinColors.instance.pal.line.withValues(alpha: 0.5)),
        ),
        child: Text(text, style: _mono(color)),
      );

  @override
  Widget build(BuildContext context) {
    final h = _health;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: DuetColors.muted),
        title: const Text('Alarm health',
            style: TextStyle(fontSize: 17, color: DuetColors.text)),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: SkinColors.instance.accent,
        backgroundColor: SkinColors.instance.pal.surface,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
          children: [
            const Text(
              'Your phone can pause apps to save battery. These settings keep '
              'your alarm running.',
              style: TextStyle(fontSize: 14, color: DuetColors.muted, height: 1.5),
            ),
            const SizedBox(height: 20),

            if (h == null) ...[
              const Skeleton(height: 64, radius: 20),
              const SizedBox(height: 8),
              const Skeleton(height: 64, radius: 20),
              const SizedBox(height: 8),
              const Skeleton(height: 64, radius: 20),
            ] else ...[
              DuetCard(
                border: h.problemCount > 0
                    ? DuetColors.danger.withValues(alpha: 0.5)
                    : null,
                child: Row(children: [
                  Icon(
                    h.problemCount > 0
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    // Semantic, not decorative: warnings are danger red and
                    // "all clear" is the sage -- neither is the skin accent,
                    // which reads as personality, not status.
                    color: h.problemCount > 0 ? DuetColors.danger : DuetColors.success,
                    size: 26,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      h.problemCount > 0
                          ? '${h.problemCount} thing${h.problemCount == 1 ? '' : 's'} '
                              'to fix — the alarm may not ring'
                          : 'Everything the app can check looks right',
                      style: const TextStyle(color: DuetColors.text, fontSize: 14.5),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              _row('Exact alarms', h.exactAlarms, 'exactAlarms',
                  'Lets the alarm ring at the exact minute'),
              _row('Notifications', h.notifications, 'notifications',
                  'Needed for the alarm screen to appear'),
              _row('Full-screen alerts', h.fullScreenIntent, 'fullScreenIntent',
                  'Lets the alarm take over the lock screen'),
              _row('Battery unrestricted', h.batteryUnrestricted, 'battery',
                  'Stops the system pausing Duet overnight'),

              if (h.isAggressiveOem) ...[
                const SizedBox(height: 8),
                DuetCard(
                  border: DuetColors.danger.withValues(alpha: 0.35),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${h.manufacturer} — Autostart',
                        style: const TextStyle(color: DuetColors.text, fontSize: 15.5)),
                    const SizedBox(height: 6),
                    const Text(
                      'Cannot be checked from inside the app. If it is off, no '
                      'alarm survives a restart. Also worth doing: lock Duet in '
                      'Recents, and allow it to show on the lock screen.',
                      style: TextStyle(
                          color: DuetColors.dim, fontSize: 12.5, height: 1.45),
                    ),
                    const SizedBox(height: 12),
                    DuetButton('Open Autostart settings',
                        onTap: () => AlarmEngine.openSetting('autostart')),
                  ]),
                ),
              ],
            ],

            if ((h?.missedLog ?? '').isNotEmpty) ...[
              const SizedBox(height: 26),
              const SectionLabel('Missed alarms'),
              const SizedBox(height: 10),
              DuetCard(
                border: DuetColors.danger.withValues(alpha: 0.45),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text(
                    'These were due while the app was not running, so they did '
                    'not ring. Usually a restart the app was not woken after.',
                    style: TextStyle(color: DuetColors.text, fontSize: 14, height: 1.45),
                  ),
                  const SizedBox(height: 10),
                  _monoSlab(h!.missedLog.trim(), DuetColors.danger.withValues(alpha: 0.85)),
                ]),
              ),
            ],

            const SizedBox(height: 26),
            const SectionLabel('Test it'),
            const SizedBox(height: 10),
            const Text(
              'Set a test alarm, lock the phone and put it face down. That is '
              'the only way to know it works.',
              style: TextStyle(fontSize: 13, color: DuetColors.dim, height: 1.45),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: DuetButton('In 30 seconds',
                      onTap: () => _testIn(const Duration(seconds: 30)))),
              const SizedBox(width: 8),
              Expanded(
                  child: DuetButton('In 2 minutes',
                      onTap: () => _testIn(const Duration(minutes: 2)))),
            ]),
            const SizedBox(height: 8),
            // Runs the same native path that runs while the app is closed, so
            // "did my partner's new alarm actually reach this phone?" is a
            // question you can answer in a second instead of in ten minutes.
            DuetButton('Pull my partner\'s alarms now',
                icon: Icons.cloud_download_outlined, onTap: _pullNow),

            const SizedBox(height: 26),
            const SectionLabel('Evidence'),
            const SizedBox(height: 10),
            DuetCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _evidence('Fire times currently held by the system',
                    '$_armedCount armed'),
                const SizedBox(height: 14),
                // The reason, not just the red badge. A sync that has been
                // failing for days used to look identical to being offline for
                // a second, which is how a partner's alarms can quietly stop
                // arriving without anyone finding out.
                _evidence(
                    'Last sync with your partner',
                    AlarmRepository.instance.lastSyncOk
                        ? 'ok — ${AlarmRepository.instance.lastSyncDetail}'
                        : 'FAILING (${AlarmRepository.instance.lastSyncDetail}) '
                            '— ${AlarmRepository.instance.lastSyncError ?? 'no error reported'}'),
                const SizedBox(height: 14),
                _evidence('Last re-arm after restart or update',
                    (h?.lastBootReArm.isNotEmpty ?? false)
                        ? h!.lastBootReArm
                        : 'none yet — restart the phone to test'),
                const SizedBox(height: 14),
                _evidence('Alarms that actually rang',
                    (h?.ringLog.isNotEmpty ?? false) ? h!.ringLog.trim() : 'none yet'),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _evidence(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: DuetColors.muted, fontSize: 13)),
          const SizedBox(height: 6),
          _monoSlab(value, DuetColors.muted),
        ],
      );

  Widget _row(String label, bool ok, String settingKey, String why) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: DuetCard(
          child: Row(children: [
            Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
                color: ok ? DuetColors.success : DuetColors.danger, size: 20),
            const SizedBox(width: 13),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label,
                    style: const TextStyle(color: DuetColors.text, fontSize: 15)),
                const SizedBox(height: 2),
                Text(ok ? 'Allowed' : why,
                    style: TextStyle(
                        color: ok ? DuetColors.dim : DuetColors.danger.withValues(alpha: 0.8),
                        fontSize: 12.5)),
              ]),
            ),
            if (!ok)
              TextButton(
                onPressed: () async {
                  await AlarmEngine.openSetting(settingKey);
                },
                child: Text('Fix',
                    style: TextStyle(color: SkinColors.instance.accent, fontSize: 14.5)),
              ),
          ]),
        ),
      );
}
