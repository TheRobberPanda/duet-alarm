import 'dart:async';

import 'package:flutter/material.dart';

import 'alarm_engine.dart';

/// Milestone 0 harness.
///
/// The goal of this screen is not to be the product -- it is to answer one
/// question: does a phone in a drawer, offline, overnight, ring at the time it
/// was told to? Everything here exists to make that testable and to make a
/// failure visible rather than silent.
void main() => runApp(const DuetApp());

const _bg = Color(0xFF171310);
const _surface = Color(0xFF1E1815);
const _amber = Color(0xFFE9A35B);
const _teal = Color(0xFF5FB3AE);
const _text = Color(0xFFF5EDE6);
const _muted = Color(0xFFB2A398);
const _dim = Color(0xFF7C6E66);

class DuetApp extends StatelessWidget {
  const DuetApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Duet',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _bg,
          colorScheme: const ColorScheme.dark(
            primary: _amber,
            secondary: _teal,
            surface: _surface,
          ),
          fontFamily: 'sans-serif',
        ),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  List<ArmedAlarm> _armed = [];
  AlarmHealth? _health;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    // Keeps the countdown honest while the screen is open.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reconcile on every foreground: this is the loop that catches an alarm
    // that was dropped while we were not running.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    await AlarmEngine.reconcile();
    final armed = await AlarmEngine.armedAlarms();
    final health = await AlarmEngine.health();
    if (mounted) setState(() { _armed = armed; _health = health; });
  }

  Future<void> _armIn(Duration d, String label) async {
    await AlarmEngine.arm(
      id: 'test-${DateTime.now().millisecondsSinceEpoch}',
      fireAt: DateTime.now().add(d),
      label: label,
    );
    await _refresh();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.dark(
          primary: _amber, surface: _surface,
        )),
        child: child!,
      ),
    );
    if (picked == null) return;

    final now = DateTime.now();
    var fire = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
    if (!fire.isAfter(now)) fire = fire.add(const Duration(days: 1));

    await AlarmEngine.arm(
      id: 'alarm-${fire.millisecondsSinceEpoch}',
      fireAt: fire,
      label: 'Alarm',
    );
    await _refresh();
  }

  String _countdown(DateTime target) {
    var left = target.difference(DateTime.now());
    if (left.isNegative) return 'due now';
    final h = left.inHours;
    final m = left.inMinutes % 60;
    final s = left.inSeconds % 60;
    if (h > 0) return 'in ${h}h ${m}m';
    if (m > 0) return 'in ${m}m ${s}s';
    return 'in ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final h = _health;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: _amber,
          backgroundColor: _surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
            children: [
              const Text('Duet',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w500, color: _text)),
              const SizedBox(height: 4),
              const Text('Milestone 0 — does it actually ring?',
                  style: TextStyle(fontSize: 14, color: _dim)),
              const SizedBox(height: 22),

              _sectionLabel('Test the alarm'),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _button('30 seconds',
                    () => _armIn(const Duration(seconds: 30), 'Quick test'))),
                const SizedBox(width: 8),
                Expanded(child: _button('2 minutes',
                    () => _armIn(const Duration(minutes: 2), 'Lock the phone now'))),
              ]),
              const SizedBox(height: 8),
              _button('Pick a time…', _pickTime, filled: true),
              const SizedBox(height: 10),
              const Text(
                'For a real test: arm the 2-minute alarm, lock the phone, '
                'put it face down and wait. For the overnight test, arm a time, '
                'turn on airplane mode and leave it until morning.',
                style: TextStyle(fontSize: 12.5, color: _dim, height: 1.45),
              ),

              const SizedBox(height: 26),
              _sectionLabel('Armed (${_armed.length})'),
              const SizedBox(height: 10),
              if (_armed.isEmpty)
                _card(const Text('Nothing armed.',
                    style: TextStyle(color: _dim, fontSize: 14)))
              else
                ..._armed.map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _card(Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${a.fireAt.hour.toString().padLeft(2, '0')}:'
                                '${a.fireAt.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                    fontSize: 26, fontWeight: FontWeight.w300, color: _text),
                              ),
                              const SizedBox(height: 2),
                              Text('${a.label} · ${_countdown(a.fireAt)}',
                                  style: const TextStyle(fontSize: 13, color: _dim)),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () async {
                            await AlarmEngine.disarm(a.id);
                            await _refresh();
                          },
                          icon: const Icon(Icons.close, color: _dim, size: 20),
                        ),
                      ])),
                    )),

              const SizedBox(height: 26),
              _sectionLabel('Alarm health'),
              const SizedBox(height: 10),
              if (h == null)
                _card(const Text('Checking…', style: TextStyle(color: _dim)))
              else ...[
                if (h.problemCount > 0)
                  _card(
                    Row(children: [
                      const Icon(Icons.warning_amber_rounded, color: _amber, size: 26),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${h.problemCount} thing${h.problemCount == 1 ? '' : 's'} to fix — '
                          'the alarm may not ring',
                          style: const TextStyle(color: _text, fontSize: 14.5),
                        ),
                      ),
                    ]),
                    border: _amber.withValues(alpha: 0.5),
                  ),
                if (h.problemCount > 0) const SizedBox(height: 8),
                _healthRow('Exact alarms', h.exactAlarms, 'exactAlarms'),
                _healthRow('Notifications', h.notifications, 'notifications'),
                _healthRow('Full-screen alerts', h.fullScreenIntent, 'fullScreenIntent'),
                _healthRow('Battery unrestricted', h.batteryUnrestricted, 'battery'),
                if (h.isAggressiveOem)
                  _card(
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${h.manufacturer} — Autostart',
                          style: const TextStyle(color: _text, fontSize: 15)),
                      const SizedBox(height: 6),
                      const Text(
                        'Cannot be checked from inside the app. If this is off, '
                        'alarms will not survive a restart. Also: lock Duet in '
                        'Recents and allow it to show on the lock screen.',
                        style: TextStyle(color: _dim, fontSize: 12.5, height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      _button('Open Autostart settings',
                          () => AlarmEngine.openSetting('autostart')),
                    ]),
                    border: _amber.withValues(alpha: 0.35),
                  ),
              ],

              const SizedBox(height: 26),
              _sectionLabel('Evidence'),
              const SizedBox(height: 10),
              _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Last re-arm after boot / update',
                    style: TextStyle(color: _muted, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  (h?.lastBootReArm.isNotEmpty ?? false)
                      ? h!.lastBootReArm
                      : 'none yet — reboot the phone to test',
                  style: const TextStyle(color: _dim, fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                const Text('Alarms that actually rang',
                    style: TextStyle(color: _muted, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  (h?.ringLog.isNotEmpty ?? false) ? h!.ringLog.trim() : 'none yet',
                  style: const TextStyle(
                      color: _dim, fontSize: 11.5, height: 1.5, fontFamily: 'monospace'),
                ),
              ])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String s) => Text(
        s.toUpperCase(),
        style: const TextStyle(
            fontSize: 11.5, letterSpacing: 1.3, color: _dim, fontWeight: FontWeight.w600),
      );

  Widget _card(Widget child, {Color? border}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: border != null ? Border.all(color: border) : null,
        ),
        child: child,
      );

  Widget _healthRow(String label, bool ok, String settingKey) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _card(Row(children: [
          Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
              color: ok ? _teal : _amber, size: 20),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label, style: const TextStyle(color: _text, fontSize: 15))),
          if (!ok)
            TextButton(
              onPressed: () async {
                await AlarmEngine.openSetting(settingKey);
              },
              child: const Text('Fix', style: TextStyle(color: _amber, fontSize: 14.5)),
            ),
        ])),
      );

  Widget _button(String label, VoidCallback onTap, {bool filled = false}) => SizedBox(
        height: 48,
        child: filled
            ? FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: _amber,
                  foregroundColor: const Color(0xFF1B120A),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(label,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
              )
            : OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _text,
                  side: const BorderSide(color: Color(0xFF352C27)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(label, style: const TextStyle(fontSize: 15)),
              ),
      );
}
