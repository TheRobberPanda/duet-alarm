import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'alarm_engine.dart';
import 'pair_repository.dart';
import 'pair_screen.dart';
import 'sign_in_screen.dart';
import 'supabase_config.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  runApp(const DuetApp());
}

class DuetApp extends StatelessWidget {
  const DuetApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Duet',
        debugShowCheckedModeBanner: false,
        theme: duetTheme(),
        home: const AuthGate(),
      );
}

/// Signed out → sign in. Signed in → pairing, or the app.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;
        if (session == null) return const SignInScreen();
        return const PairGate();
      },
    );
  }
}

/// A user with no partner cannot do anything useful, so pairing comes before
/// the app rather than sitting in a settings screen.
class PairGate extends StatefulWidget {
  const PairGate({super.key});

  @override
  State<PairGate> createState() => _PairGateState();
}

class _PairGateState extends State<PairGate> {
  final _repo = PairRepository.instance();
  Future<PairState?>? _pair;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _pair = _repo.currentPair());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PairState?>(
      future: _pair,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: DuetColors.amber)),
          );
        }
        final pair = snap.data;
        if (pair == null || !pair.isComplete) {
          return PairScreen(onPaired: _reload);
        }
        return HomePage(pair: pair, onPairChanged: _reload);
      },
    );
  }
}

/// Milestone 0's alarm harness, now with the pair it belongs to.
///
/// Still a harness, not the product: the question it answers is whether a phone
/// in a drawer rings when it was told to. Milestone 3 replaces it with real
/// shared alarms.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.pair, required this.onPairChanged});

  final PairState pair;
  final VoidCallback onPairChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _repo = PairRepository.instance();
  List<ArmedAlarm> _armed = [];
  AlarmHealth? _health;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
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
    // dropped while we were not running.
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

  String _countdown(DateTime target) {
    final left = target.difference(DateTime.now());
    if (left.isNegative) return 'due now';
    final h = left.inHours, m = left.inMinutes % 60, s = left.inSeconds % 60;
    if (h > 0) return 'in ${h}h ${m}m';
    if (m > 0) return 'in ${m}m ${s}s';
    return 'in ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final h = _health;
    final partner = widget.pair.partner!;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: DuetColors.amber,
          backgroundColor: DuetColors.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 40),
            children: [
              _partnerStrip(partner),
              const SizedBox(height: 24),

              const SectionLabel('Test the alarm'),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: DuetButton('30 seconds',
                    onTap: () => _armIn(const Duration(seconds: 30), 'Quick test'))),
                const SizedBox(width: 8),
                Expanded(child: DuetButton('2 minutes',
                    onTap: () => _armIn(const Duration(minutes: 2), 'Lock the phone now'))),
              ]),
              const SizedBox(height: 10),
              const Text(
                'For the overnight test: arm a time, turn on airplane mode, '
                'and leave the phone in a drawer until morning.',
                style: TextStyle(fontSize: 12.5, color: DuetColors.dim, height: 1.45),
              ),

              const SizedBox(height: 26),
              SectionLabel('Armed (${_armed.length})'),
              const SizedBox(height: 10),
              if (_armed.isEmpty)
                const DuetCard(
                    child: Text('Nothing armed.',
                        style: TextStyle(color: DuetColors.dim, fontSize: 14)))
              else
                ..._armed.map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DuetCard(
                        child: Row(children: [
                          const PairRing(size: 26, strokeWidth: 2),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${a.fireAt.hour.toString().padLeft(2, '0')}:'
                                  '${a.fireAt.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w300,
                                      color: DuetColors.text),
                                ),
                                const SizedBox(height: 2),
                                Text('${a.label} · ${_countdown(a.fireAt)}',
                                    style: const TextStyle(
                                        fontSize: 13, color: DuetColors.dim)),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () async {
                              await AlarmEngine.disarm(a.id);
                              await _refresh();
                            },
                            icon: const Icon(Icons.close, color: DuetColors.dim, size: 20),
                          ),
                        ]),
                      ),
                    )),

              const SizedBox(height: 26),
              const SectionLabel('Alarm health'),
              const SizedBox(height: 10),
              if (h == null)
                const DuetCard(child: Text('Checking…', style: TextStyle(color: DuetColors.dim)))
              else ...[
                if (h.problemCount > 0) ...[
                  DuetCard(
                    border: DuetColors.amber.withValues(alpha: 0.5),
                    child: Row(children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: DuetColors.amber, size: 26),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${h.problemCount} thing${h.problemCount == 1 ? '' : 's'} to fix '
                          '— the alarm may not ring',
                          style: const TextStyle(color: DuetColors.text, fontSize: 14.5),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                ],
                _healthRow('Exact alarms', h.exactAlarms, 'exactAlarms'),
                _healthRow('Notifications', h.notifications, 'notifications'),
                _healthRow('Full-screen alerts', h.fullScreenIntent, 'fullScreenIntent'),
                _healthRow('Battery unrestricted', h.batteryUnrestricted, 'battery'),
                if (h.isAggressiveOem)
                  DuetCard(
                    border: DuetColors.amber.withValues(alpha: 0.35),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${h.manufacturer} — Autostart',
                          style: const TextStyle(color: DuetColors.text, fontSize: 15)),
                      const SizedBox(height: 6),
                      const Text(
                        'Cannot be checked from inside the app. If this is off, '
                        'alarms will not survive a restart.',
                        style: TextStyle(color: DuetColors.dim, fontSize: 12.5, height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      DuetButton('Open Autostart settings',
                          onTap: () => AlarmEngine.openSetting('autostart')),
                    ]),
                  ),
              ],

              if ((h?.missedLog ?? '').isNotEmpty) ...[
                const SizedBox(height: 26),
                const SectionLabel('Missed alarms'),
                const SizedBox(height: 10),
                DuetCard(
                  border: DuetColors.amber,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text(
                      'These were due while the app was not running — they did not ring.',
                      style: TextStyle(color: DuetColors.text, fontSize: 14, height: 1.45),
                    ),
                    const SizedBox(height: 10),
                    Text(h!.missedLog.trim(),
                        style: const TextStyle(
                            color: DuetColors.amber,
                            fontSize: 11.5,
                            height: 1.5,
                            fontFamily: 'monospace')),
                  ]),
                ),
              ],

              const SizedBox(height: 26),
              const SectionLabel('Evidence'),
              const SizedBox(height: 10),
              DuetCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Last re-arm after boot / update',
                      style: TextStyle(color: DuetColors.muted, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    (h?.lastBootReArm.isNotEmpty ?? false)
                        ? h!.lastBootReArm
                        : 'none yet — reboot the phone to test',
                    style: const TextStyle(color: DuetColors.dim, fontSize: 12.5),
                  ),
                  const SizedBox(height: 14),
                  const Text('Alarms that actually rang',
                      style: TextStyle(color: DuetColors.muted, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    (h?.ringLog.isNotEmpty ?? false) ? h!.ringLog.trim() : 'none yet',
                    style: const TextStyle(
                        color: DuetColors.dim,
                        fontSize: 11.5,
                        height: 1.5,
                        fontFamily: 'monospace'),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _partnerStrip(Profile partner) => DuetCard(
        child: Row(children: [
          const PairRing(size: 34, strokeWidth: 2),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('You and ${partner.shortName}',
                    style: const TextStyle(
                        fontSize: 15.5, color: DuetColors.text, fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                Text(partner.timezone,
                    style: const TextStyle(fontSize: 12.5, color: DuetColors.dim)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: DuetColors.dim, size: 22),
            onPressed: _openAccountSheet,
          ),
        ]),
      );

  Widget _healthRow(String label, bool ok, String settingKey) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: DuetCard(
          child: Row(children: [
            Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
                color: ok ? DuetColors.teal : DuetColors.amber, size: 20),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: const TextStyle(color: DuetColors.text, fontSize: 15))),
            if (!ok)
              TextButton(
                onPressed: () => AlarmEngine.openSetting(settingKey),
                child: const Text('Fix',
                    style: TextStyle(color: DuetColors.amber, fontSize: 14.5)),
              ),
          ]),
        ),
      );

  void _openAccountSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: DuetColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SectionLabel('Account'),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link_off, color: DuetColors.muted),
              title: Text('Unpair from ${widget.pair.partner!.shortName}',
                  style: const TextStyle(color: DuetColors.text)),
              subtitle: const Text('Alarms go back to being personal',
                  style: TextStyle(color: DuetColors.dim, fontSize: 12.5)),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _repo.leavePair();
                widget.onPairChanged();
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout, color: DuetColors.muted),
              title: const Text('Sign out', style: TextStyle(color: DuetColors.text)),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _repo.signOut();
              },
            ),
            const Divider(color: DuetColors.line),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline, color: DuetColors.danger),
              title: const Text('Delete my account',
                  style: TextStyle(color: DuetColors.danger)),
              subtitle: const Text('Permanent. Removes all your alarms.',
                  style: TextStyle(color: DuetColors.dim, fontSize: 12.5)),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _confirmDelete();
              },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: DuetColors.surfaceRaised,
        title: const Text('Delete your account?',
            style: TextStyle(color: DuetColors.text)),
        content: const Text(
          'This removes your profile, your alarms and your pairing. '
          'It cannot be undone.',
          style: TextStyle(color: DuetColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: DuetColors.dim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: DuetColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deleteAccount();
  }
}
